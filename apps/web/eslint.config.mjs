import { defineConfig, globalIgnores } from "eslint/config";
import nextVitals from "eslint-config-next/core-web-vitals";
import nextTs from "eslint-config-next/typescript";

const eslintConfig = defineConfig([
  ...nextVitals,
  ...nextTs,
  {
    files: ["components/lessons/**/*.{ts,tsx}", "app/learn/**/lesson-content.tsx"],
    rules: {
      // These classes previously depended on the route's CSS contrast floor.
      // Cover class attributes, data strings and template-string fragments.
      "no-restricted-syntax": [
        "error",
        {
          selector: "Literal[value=/(?:^|[\\s:])text-white\\u002F(?:[0-4]?[0-9](?:[.][0-9]+)?|50(?:[.]0+)?)(?:\\s|$)/]",
          message: "Use text-muted-foreground for secondary lesson text instead of low-opacity white classes.",
        },
        {
          selector: "TemplateElement[value.raw=/(?:^|[\\s:])text-white\\u002F(?:[0-4]?[0-9](?:[.][0-9]+)?|50(?:[.]0+)?)(?:\\s|$)/]",
          message: "Use text-muted-foreground for secondary lesson text instead of low-opacity white classes.",
        },
      ],
    },
  },
  // Override default ignores of eslint-config-next.
  globalIgnores([
    // Default ignores of eslint-config-next:
    ".next/**",
    ".next*/**",
    ".next_trash*/**",
    ".next_backup/**",
    "out/**",
    "build/**",
    "next-env.d.ts",
    // Test artifacts:
    "playwright-report/**",
    "test-results/**",
  ]),
]);

export default eslintConfig;
