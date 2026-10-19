/**
 * LearnX AI_Proxy Cloud Functions entry point.
 *
 * Exposes the provider abstraction surface plus the metered AI callables. Each
 * callable's implementation lives under `./callables`; the heavy lifting
 * (metering gate order, moderation, provider abstraction) lives in `./ai`.
 */
export * from "./ai";
export { config } from "./config";

// Metered AI callables. Exporting them here registers them for deployment.
export { chatWithTeacher } from "./callables/chat";
export { generatePlacementQuestion } from "./callables/placement";
export { personalizeLesson } from "./callables/personalize_lesson";
export { deleteMyData } from "./callables/delete_my_data";

// Scheduled maintenance functions.
export { generateWeeklySummaries } from "./scheduled/weekly_summary";
