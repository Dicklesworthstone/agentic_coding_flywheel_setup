import {
  COMPLETE_GUIDE_PHASE_COUNT,
  COMPLETE_GUIDE_PROMPT_COUNT,
  VALIDATION_GATES,
} from "@/lib/complete-guide";
import { createSocialImage } from "@/lib/social-image";
import { getStaticRouteSocialData, socialImageAlt } from "@/lib/social-image-routes";

const data = {
  ...getStaticRouteSocialData("/complete-guide"),
  stats: [
    { value: String(COMPLETE_GUIDE_PROMPT_COUNT), label: "Copy-ready prompts" },
    { value: String(COMPLETE_GUIDE_PHASE_COUNT), label: "Workflow phases" },
    { value: String(VALIDATION_GATES.length), label: "Validation gates" },
  ],
};

export const alt = socialImageAlt(data);
export const size = { width: 1200, height: 630 };
export const contentType = "image/png";
// Share card design 2: see SOCIAL_CARD_DESIGN in lib/social-image.tsx.

export default function Image() {
  return createSocialImage(data, "opengraph");
}
