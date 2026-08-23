import { createSocialImage } from "@/lib/social-image";
import { getStaticRouteSocialData } from "@/lib/social-image-routes";

export const runtime = "edge";

export const alt = "ACFS on Omarchy — The Flywheel, Native on Arch";
export const size = {
  width: 1200,
  height: 630,
};
export const contentType = "image/png";

export default function Image() {
  return createSocialImage(getStaticRouteSocialData("/omarchy"), "opengraph");
}
