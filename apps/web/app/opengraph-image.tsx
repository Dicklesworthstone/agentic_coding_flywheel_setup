import { createSocialImage } from "@/lib/social-image";
import { getStaticRouteSocialData, socialImageAlt } from "@/lib/social-image-routes";

const data = getStaticRouteSocialData("/");

export const alt = socialImageAlt(data);
export const size = { width: 1200, height: 630 };
export const contentType = "image/png";
// Share card design 2: see SOCIAL_CARD_DESIGN in lib/social-image.tsx.

export default function Image() {
  return createSocialImage(data, "opengraph");
}
