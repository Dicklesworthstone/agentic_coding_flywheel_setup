// Regenerate the production artwork after editing renderCloudAgentSocialImage.
// PNGs are bundled as data so the existing Edge routes need no filesystem or
// external fetch. This writes image data only, not application source code.
import { randomUUID } from "node:crypto";
import { renameSync, writeFileSync } from "node:fs";
import { renderCloudAgentSocialImage } from "../lib/social-image.tsx";

const images = {};
for (const [variant, height] of [["opengraph", 630], ["twitter", 600]]) {
  const response = renderCloudAgentSocialImage(variant);
  const bytes = Buffer.from(await response.arrayBuffer());
  if (response.status !== 200 || bytes.length <= 4096 ||
      !bytes.subarray(0, 8).equals(Buffer.from([137, 80, 78, 71, 13, 10, 26, 10])) ||
      bytes.readUInt32BE(16) !== 1200 || bytes.readUInt32BE(20) !== height) {
    throw new Error(`Invalid ${variant} artwork; existing image data was not changed`);
  }
  images[variant] = bytes.toString("base64");
}
// Prepare both variants and the complete file before replacing existing data.
const destination = new URL("../lib/cloud-social-images.json", import.meta.url);
const temporary = new URL(`./cloud-social-images-${randomUUID()}.json`, destination);
writeFileSync(temporary, JSON.stringify(images) + "\n", { flag: "wx" });
renameSync(temporary, destination);
console.log("Rendered both cloud share-image assets (1200×630 and 1200×600)");
