#!/usr/bin/env node
import { readContent, validateContent } from './content-lib.mjs';

const content = readContent();
const { errors, summary } = validateContent(content);

if (errors.length) {
  console.error(`Found ${errors.length} content data issue(s):`);
  errors.forEach((error) => console.error(`- ${error}`));
  process.exit(1);
}

const usageSummary = summary.trackUsage
  .map(([trackId, count]) => `${trackId}:${count}`)
  .join(', ');

console.log(`Validated ${summary.videos} video record(s), ${summary.publishedVideos} published.`);
console.log(`Validated ${summary.ambientTracks} ambient track(s), ${summary.ambientRules} rule(s).`);
console.log(`Validated ${summary.videoAudioMixes} explicit video mix override(s).`);
console.log(
  `Resolved ambient audio for ${summary.videosWithAudio}/${summary.publishedVideos} published video(s); `
    + `${summary.videosWithoutAudio} without audio.`,
);
console.log(`Track usage: ${usageSummary || 'none'}`);
