import { createSocialImage } from "@/lib/social-image";
import { getStaticRouteSocialData, socialImageAlt } from "@/lib/social-image-routes";

// Served from the pre-rendered PNGs in lib/cloud-social-images.json.
const data = getStaticRouteSocialData("/cloud-agents");

export const runtime = "edge";
export const alt = socialImageAlt(data);
export const size = { width: 1200, height: 600 };
export const contentType = "image/png";

export default function Image() {
  return createSocialImage(data, "twitter");
}
