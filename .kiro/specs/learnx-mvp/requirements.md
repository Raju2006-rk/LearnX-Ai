# Requirements Document

## Introduction

LearnX is a cross-platform English-learning application built on a single Flutter codebase (mobile, web, desktop) with a Firebase backend (Authentication, Firestore, Cloud Functions). The MVP (Phase 1) delivers five capability areas: account sign-up and adaptive onboarding, a guided home learning path, an AI English Teacher chat with instant grammar feedback, daily quizzes with spaced repetition, and progress tracking with rewards.

All AI generation is provider-abstracted (default Google Gemini via Firebase AI Logic / Vertex AI, swappable) and routed exclusively through Cloud Functions so provider keys stay server-side and usage limits are enforced centrally. This document specifies WHAT the MVP must do, expressed as EARS-pattern acceptance criteria, and explicitly lists what is out of scope while ensuring the design does not block those future capabilities.

## Glossary

- **LearnX_App**: The Flutter client application running on mobile, web, or desktop.
- **Auth_Service**: The Firebase Authentication–backed subsystem that manages sign-up, sign-in, and session state.
- **Onboarding_Service**: The subsystem that collects a learner's starting profile (English level, goal, native language) and runs the placement test.
- **Placement_Test**: An adaptive quiz that maps a learner's responses to a CEFR-like level (A1, A2, B1, B2, C1).
- **Learning_Path_Service**: The subsystem that presents pre-authored sections, weeks, and steps and manages step locking and unlocking.
- **Step**: A single learning unit shown as a circle on the learning path.
- **Content_Store**: The Firestore-backed store holding the pre-authored learning-path skeleton and cached content.
- **AI_Proxy**: The Cloud Functions service that mediates every AI request, applies moderation, and enforces usage limits.
- **AI_Teacher**: The AI English Teacher chat feature that replies to learner messages and returns grammar feedback.
- **Grammar_Feedback**: A structured AI response containing the flagged mistake, the corrected sentence, a short tip, and a native-language translation.
- **Quiz_Service**: The subsystem that delivers daily quizzes and scores answers.
- **Review_Queue**: The store of previously incorrect quiz items scheduled for repeated presentation (spaced-repetition style).
- **Progress_Service**: The subsystem that tracks streaks, daily goal, badges, and weekly summaries.
- **Streak**: The count of consecutive days on which the learner completes at least one qualifying activity.
- **Badge**: A reward tier awarded for progress milestones, one of Bronze, Silver, or Gold.
- **Usage_Limit**: A server-enforced cap on a metered action (for example, daily AI chats) applied per account tier.
- **Account_Tier**: The learner's entitlement level, either Free or Premium.
- **Native_Language**: The learner's chosen first language, one of Hindi, Tamil, Telugu, Bengali, or Marathi.
- **Sync_Service**: The subsystem that synchronizes account and progress data across a learner's devices.
- **Offline_Cache**: The local data layer on mobile that stores pre-authored lesson content for offline read and practice.
- **DPDP_Act**: The Digital Personal Data Protection Act, the data-protection regime LearnX must comply with.

## Requirements

### Requirement 1: Sign-up and Authentication

**User Story:** As a new learner, I want to sign up and sign in using a method I already have, so that I can access LearnX quickly and securely.

#### Acceptance Criteria

1. WHERE the learner selects phone sign-in, THE Auth_Service SHALL authenticate the learner using a phone-number one-time-code flow.
2. WHERE the learner selects Google sign-in, THE Auth_Service SHALL authenticate the learner using a Google account.
3. WHERE the learner selects email sign-in, THE Auth_Service SHALL authenticate the learner using an email-and-password credential.
4. WHEN authentication succeeds, THE Auth_Service SHALL create or restore the learner account and establish a signed-in session.
5. IF authentication fails, THEN THE Auth_Service SHALL display an error message and keep the learner on the sign-in screen.
6. WHEN a signed-in learner reopens the LearnX_App, THE Auth_Service SHALL restore the existing session without requiring re-authentication.

### Requirement 2: Onboarding and Adaptive Placement

**User Story:** As a new learner, I want to set my level, goal, and native language and take a placement test, so that my learning is personalized from the start.

#### Acceptance Criteria

1. WHEN a learner completes first authentication, THE Onboarding_Service SHALL prompt the learner to select a current English level.
2. WHEN onboarding is in progress, THE Onboarding_Service SHALL prompt the learner to select a goal of Speaking, Job, or Both.
3. WHEN onboarding is in progress, THE Onboarding_Service SHALL prompt the learner to select a Native_Language from Hindi, Tamil, Telugu, Bengali, or Marathi.
4. WHEN the learner starts the placement test, THE Placement_Test SHALL present adaptive questions whose difficulty adjusts based on prior answers.
5. WHEN the learner completes the Placement_Test, THE Placement_Test SHALL assign a CEFR-like level of A1, A2, B1, B2, or C1 and store the level on the learner profile.
6. WHEN onboarding selections and placement results are stored, THE Onboarding_Service SHALL mark the profile as onboarded and route the learner to the home learning path.

### Requirement 3: Home Learning Path

**User Story:** As a learner, I want a guided path of steps that unlock as I progress, so that I always know what to do next.

#### Acceptance Criteria

1. THE Learning_Path_Service SHALL present pre-authored sections, weeks, and steps sourced from the Content_Store.
2. THE Learning_Path_Service SHALL render each Step as a circle indicating its locked, available, or completed state.
3. WHILE a Step's preceding Step is not completed, THE Learning_Path_Service SHALL keep the Step locked and prevent the learner from starting it.
4. WHEN a learner completes a Step, THE Learning_Path_Service SHALL mark the Step completed and unlock the next Step.
5. WHEN a learner opens a Step, THE Learning_Path_Service SHALL combine the pre-authored skeleton with AI-personalized examples and practice returned by the AI_Proxy.
6. IF the AI_Proxy does not return personalized content, THEN THE Learning_Path_Service SHALL present the pre-authored skeleton content for the Step.
7. WHEN a learner completes at least one qualifying activity on a calendar day, THE Progress_Service SHALL increment the daily Streak and display the streak flame indicator.

### Requirement 4: AI English Teacher Chat

**User Story:** As a learner, I want to chat with an AI English teacher and get instant grammar feedback in a language I understand, so that I can improve my English through conversation.

#### Acceptance Criteria

1. WHEN a learner sends a text message in the AI_Teacher chat, THE AI_Proxy SHALL forward the request to the configured AI provider and return a reply.
2. WHEN the AI_Teacher returns feedback on a learner message, THE AI_Teacher SHALL display the flagged mistake styled in red and the corrected sentence styled in green.
3. WHEN the AI_Teacher returns Grammar_Feedback, THE AI_Teacher SHALL include a short tip and a translation in the learner's selected Native_Language.
4. WHEN the learner submits a chat message, THE AI_Teacher SHALL begin displaying the reply within 2 seconds under nominal network conditions.
5. IF the network is unavailable, THEN THE AI_Teacher SHALL inform the learner that chat requires a network connection and SHALL NOT queue the message silently.
6. WHERE the learner's Account_Tier is Free, THE AI_Proxy SHALL enforce the configured daily Usage_Limit on AI chat messages and reject requests that exceed the limit with a limit-reached response.

### Requirement 5: AI Safety and Moderation

**User Story:** As a learner (or a parent of a young learner), I want the AI teacher to stay safe and correct, so that I can trust the feedback and flag problems.

#### Acceptance Criteria

1. WHEN the AI_Proxy processes a chat request or response, THE AI_Proxy SHALL apply content moderation to keep both input and output age-appropriate for all ages.
2. IF moderation flags a learner message or an AI reply as unsafe, THEN THE AI_Proxy SHALL withhold the unsafe content and return a safe substitute or refusal message.
3. THE AI_Teacher SHALL present a report-a-wrong-correction affordance on each Grammar_Feedback item.
4. WHEN a learner reports a wrong correction, THE AI_Teacher SHALL record the reported item with its context for later review and confirm receipt to the learner.

### Requirement 6: Daily Quizzes and Spaced Repetition

**User Story:** As a learner, I want daily quizzes that revisit my mistakes, so that I reinforce what I get wrong.

#### Acceptance Criteria

1. WHEN a learner starts a daily quiz, THE Quiz_Service SHALL present fill-in-the-blank and choose-the-right-word questions.
2. WHEN a learner completes a quiz, THE Quiz_Service SHALL display the count of correct answers and the count of wrong answers.
3. WHEN a learner answers a question incorrectly, THE Quiz_Service SHALL add the question to the Review_Queue.
4. WHEN a learner starts a later quiz session, THE Quiz_Service SHALL reintroduce items due from the Review_Queue on a spaced-repetition schedule.
5. WHEN a learner answers a Review_Queue item correctly, THE Quiz_Service SHALL advance that item to a longer review interval.
6. IF the network is unavailable, THEN THE Quiz_Service SHALL inform the learner that quizzes require a network connection.

### Requirement 7: Progress and Rewards

**User Story:** As a learner, I want to see my streaks, goals, badges, and a weekly summary, so that I stay motivated.

#### Acceptance Criteria

1. THE Progress_Service SHALL display the learner's current Streak and longest Streak.
2. THE Progress_Service SHALL display a daily goal tracker spanning Day 1 through Day 15 and continuing beyond Day 15.
3. WHEN a learner reaches a defined progress milestone, THE Progress_Service SHALL award the corresponding Badge of Bronze, Silver, or Gold.
4. THE Progress_Service SHALL display a weekly summary containing time spent, words learned, and mistakes fixed.
5. WHEN a learner completes a qualifying activity, THE Progress_Service SHALL update the current Streak, daily goal tracker, and weekly summary metrics.

### Requirement 8: Offline Content and Data Sync

**User Story:** As a learner on a mobile device with intermittent connectivity, I want pre-authored lessons available offline and my progress synced across devices, so that I can keep learning anywhere.

#### Acceptance Criteria

1. WHILE the LearnX_App runs on a mobile device and pre-authored lesson content is cached, THE Offline_Cache SHALL allow the learner to read and practice that content without a network connection.
2. WHEN network connectivity is restored, THE Sync_Service SHALL synchronize locally recorded progress with the Firestore backend.
3. WHEN a learner signs in on a different device, THE Sync_Service SHALL restore the learner's account and progress state on that device.
4. THE AI_Teacher and Quiz_Service SHALL require an active network connection to operate.

### Requirement 9: Performance

**User Story:** As a learner on a low-end phone and a slow network, I want the app to open fast and respond quickly, so that learning feels smooth.

#### Acceptance Criteria

1. WHEN a learner launches the LearnX_App, THE LearnX_App SHALL display the initial interactive screen within 3 seconds under nominal conditions.
2. WHEN a learner submits an AI chat message, THE AI_Teacher SHALL begin displaying a reply within 2 seconds under nominal network conditions.
3. THE LearnX_App SHALL remain operable on low-end mobile devices and on slow network connections.

### Requirement 10: Security, Privacy, and Compliance

**User Story:** As a learner, I want my data protected and handled lawfully, so that I can trust LearnX with my personal information.

#### Acceptance Criteria

1. THE LearnX_App SHALL encrypt learner data in transit and at rest.
2. THE AI_Proxy SHALL keep AI provider credentials server-side and SHALL NOT expose them to the LearnX_App client.
3. THE LearnX_App SHALL handle personal data in compliance with the DPDP_Act, including collecting consent for personal-data processing.
4. THE LearnX_App SHALL present content that is safe and age-appropriate for all ages.

### Requirement 11: AI Provider Abstraction and Usage Limits

**User Story:** As the product owner, I want AI providers to be swappable and usage limits enforced centrally, so that we control cost and can change providers without client changes.

#### Acceptance Criteria

1. THE AI_Proxy SHALL route every AI generation request through Cloud Functions rather than allowing direct client-to-provider calls.
2. THE AI_Proxy SHALL expose a provider-abstraction interface whose default implementation is Google Gemini via Firebase AI Logic / Vertex AI and that supports swapping the provider without client changes.
3. THE AI_Proxy SHALL evaluate each metered request against the learner's Account_Tier and applicable Usage_Limit before invoking the AI provider.
4. IF a request exceeds the applicable Usage_Limit, THEN THE AI_Proxy SHALL reject the request with a limit-reached response and SHALL NOT invoke the AI provider.

### Requirement 12: Navigation Shell

**User Story:** As a learner, I want a consistent bottom navigation, so that I can move between core areas easily.

#### Acceptance Criteria

1. THE LearnX_App SHALL present a bottom navigation bar with Home, AI, and Account destinations.
2. WHEN a learner selects a bottom navigation destination, THE LearnX_App SHALL display the corresponding screen.
3. WHERE a Premium destination is shown in navigation for the MVP, THE LearnX_App SHALL present it as a placeholder screen.

## Out of Scope (Phase 1)

The following are explicitly out of scope for the MVP. The design MUST NOT preclude adding them later.

- Premium subscription purchase, billing, and full Premium feature set (only the server-side Usage_Limit enforcement hook is in scope).
- Voice or speech recognition, pronunciation scoring, and audio conversation with the AI teacher.
- Social features such as friends, leaderboards, group challenges, and chat between learners.
- Native languages beyond Hindi, Tamil, Telugu, Bengali, and Marathi (the set is extensible later).
- Learner-authored or teacher-authored custom content and a content-authoring CMS.
- Push-notification campaigns and re-engagement messaging.
- Full offline support for AI chat and quizzes (only pre-authored lesson content is available offline).
- Advanced analytics dashboards and admin reporting beyond the learner-facing weekly summary.
