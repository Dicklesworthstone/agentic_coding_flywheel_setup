import { createSocialImage } from "@/lib/social-image";
import { getStaticRouteSocialData } from "@/lib/social-image-routes";

export const runtime = "edge";
export const alt = "The Core Flywheel - Agent Mail, Beads & bv";
export const size = { width: 1200, height: 630 };
export const contentType = "image/png";

export default async function Image() {
  return createSocialImage(getStaticRouteSocialData("/core-flywheel"), "opengraph");
}
