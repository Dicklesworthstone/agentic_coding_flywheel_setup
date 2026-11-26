import { flywheelTools } from "@/lib/flywheel";
import { createSocialImage } from "@/lib/social-image";
import { getStaticRouteSocialData, socialImageAlt } from "@/lib/social-image-routes";

// The count comes from the catalog the page renders, like the layout's description.
const data = {
  ...getStaticRouteSocialData("/flywheel"),
  badge: `${flywheelTools.length} connected tools`,
};

export const runtime = "edge";
export const alt = socialImageAlt(data);
export const size = { width: 1200, height: 630 };
export const contentType = "image/png";
// Share card design 2: see SOCIAL_CARD_DESIGN in lib/social-image.tsx.

export default function Image() {
  return createSocialImage(data, "opengraph");
}
