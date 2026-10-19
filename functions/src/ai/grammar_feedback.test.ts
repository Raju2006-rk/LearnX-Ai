import {
  GRAMMAR_FEEDBACK_SCHEMA,
  GrammarFeedback,
  GrammarFeedbackValidationError,
  TRANSLATION_LANGUAGES,
  validateGrammarFeedback,
} from "./grammar_feedback";

/** A valid feedback object with a mistake flagged. */
function feedbackWithMistake(): Record<string, unknown> {
  return {
    hasMistake: true,
    mistakeSpan: { start: 0, end: 3, text: "She" },
    correctedSentence: "She goes to school.",
    tip: "Use the third-person singular 'goes'.",
    translation: { language: "hi", text: "वह स्कूल जाती है।" },
  };
}

/** A valid feedback object with no mistake. */
function feedbackNoMistake(): Record<string, unknown> {
  return {
    hasMistake: false,
    correctedSentence: "She goes to school.",
    tip: "Great, this sentence is correct!",
    translation: { language: "ta", text: "அவள் பள்ளிக்குச் செல்கிறாள்." },
  };
}

describe("GRAMMAR_FEEDBACK_SCHEMA", () => {
  it("requires the four core fields and not mistakeSpan", () => {
    expect(GRAMMAR_FEEDBACK_SCHEMA.required).toEqual([
      "hasMistake",
      "correctedSentence",
      "tip",
      "translation",
    ]);
  });

  it("constrains translation.language to the supported native languages", () => {
    const properties = GRAMMAR_FEEDBACK_SCHEMA.properties as Record<
      string,
      { properties: { language: { enum: string[] } } }
    >;
    expect(properties.translation.properties.language.enum).toEqual([
      ...TRANSLATION_LANGUAGES,
    ]);
  });
});

describe("validateGrammarFeedback - valid input", () => {
  it("accepts and returns feedback with a mistake span", () => {
    const result = validateGrammarFeedback(feedbackWithMistake());
    const expected: GrammarFeedback = {
      hasMistake: true,
      mistakeSpan: { start: 0, end: 3, text: "She" },
      correctedSentence: "She goes to school.",
      tip: "Use the third-person singular 'goes'.",
      translation: { language: "hi", text: "वह स्कूल जाती है।" },
    };
    expect(result).toEqual(expected);
  });

  it("accepts feedback with no mistake and omits mistakeSpan", () => {
    const result = validateGrammarFeedback(feedbackNoMistake());
    expect(result.hasMistake).toBe(false);
    expect(result).not.toHaveProperty("mistakeSpan");
  });

  it("accepts every supported translation language", () => {
    for (const language of TRANSLATION_LANGUAGES) {
      const input = { ...feedbackNoMistake(), translation: { language, text: "x" } };
      expect(validateGrammarFeedback(input).translation.language).toBe(language);
    }
  });

  it("drops mistakeSpan when hasMistake is false even if provided", () => {
    const input = {
      ...feedbackNoMistake(),
      mistakeSpan: { start: 0, end: 2, text: "no" },
    };
    const result = validateGrammarFeedback(input);
    expect(result).not.toHaveProperty("mistakeSpan");
  });

  it("ignores unexpected extra properties", () => {
    const input = { ...feedbackWithMistake(), extra: "ignored" };
    expect(validateGrammarFeedback(input)).not.toHaveProperty("extra");
  });
});

describe("validateGrammarFeedback - invalid input", () => {
  it("rejects non-object input", () => {
    expect(() => validateGrammarFeedback(null)).toThrow(
      GrammarFeedbackValidationError,
    );
    expect(() => validateGrammarFeedback("nope")).toThrow(/JSON object/);
    expect(() => validateGrammarFeedback([])).toThrow(GrammarFeedbackValidationError);
  });

  it("rejects a missing or non-boolean hasMistake", () => {
    const input = feedbackWithMistake();
    delete input.hasMistake;
    expect(() => validateGrammarFeedback(input)).toThrow(/hasMistake/);
    expect(() =>
      validateGrammarFeedback({ ...feedbackWithMistake(), hasMistake: "yes" }),
    ).toThrow(/hasMistake/);
  });

  it("rejects a missing correctedSentence", () => {
    const input = feedbackNoMistake();
    delete input.correctedSentence;
    expect(() => validateGrammarFeedback(input)).toThrow(/correctedSentence/);
  });

  it("rejects a missing tip", () => {
    const input = feedbackNoMistake();
    delete input.tip;
    expect(() => validateGrammarFeedback(input)).toThrow(/tip/);
  });

  it("rejects missing translation", () => {
    const input = feedbackNoMistake();
    delete input.translation;
    expect(() => validateGrammarFeedback(input)).toThrow(/translation/);
  });

  it("rejects an unsupported translation language", () => {
    const input = {
      ...feedbackNoMistake(),
      translation: { language: "fr", text: "Bonjour" },
    };
    expect(() => validateGrammarFeedback(input)).toThrow(/translation.language/);
  });

  it("rejects a non-string translation text", () => {
    const input = {
      ...feedbackNoMistake(),
      translation: { language: "hi", text: 42 },
    };
    expect(() => validateGrammarFeedback(input)).toThrow(/translation.text/);
  });

  it("requires mistakeSpan when hasMistake is true", () => {
    const input = feedbackWithMistake();
    delete input.mistakeSpan;
    expect(() => validateGrammarFeedback(input)).toThrow(
      /mistakeSpan is required/,
    );
  });

  it("rejects a mistakeSpan with a non-integer index", () => {
    const input = {
      ...feedbackWithMistake(),
      mistakeSpan: { start: 0.5, end: 3, text: "She" },
    };
    expect(() => validateGrammarFeedback(input)).toThrow(/mistakeSpan.start/);
  });

  it("rejects a mistakeSpan with a non-string text", () => {
    const input = {
      ...feedbackWithMistake(),
      mistakeSpan: { start: 0, end: 3, text: 3 },
    };
    expect(() => validateGrammarFeedback(input)).toThrow(/mistakeSpan.text/);
  });
});
