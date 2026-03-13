import { createSocialImage } from "@/lib/social-image";
import { getStaticRouteSocialData } from "@/lib/social-image-routes";

export const alt = "Agent Flywheel";
export const size = {
  width: 1200,
  height: 600,
};
export const contentType = "image/png";

export default function Image() {
  return createSocialImage(getStaticRouteSocialData("/"), "twitter");
}
