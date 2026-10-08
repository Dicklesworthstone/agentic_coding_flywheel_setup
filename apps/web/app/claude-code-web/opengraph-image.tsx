import { createSocialImage } from "@/lib/social-image";
import { getStaticRouteSocialData } from "@/lib/social-image-routes";

export const runtime = "edge";

export const alt = "ACFS for Claude Code on the web — the flywheel in every cloud session";
export const size = {
  width: 1200,
  height: 630,
};
export const contentType = "image/png";

export default function Image() {
  return createSocialImage(getStaticRouteSocialData("/claude-code-web"), "opengraph");
}
