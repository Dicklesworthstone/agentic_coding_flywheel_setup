import localFont from "next/font/local";

/**
 * Display serif for the long-form guides (/complete-guide, /core-flywheel).
 * Imported only by those layouts so other routes never preload it.
 * Instrument Serif is OFL-licensed (see InstrumentSerif.LICENSE.txt); the
 * woff2 files are Latin subsets.
 */
export const instrumentSerif = localFont({
  src: [
    { path: "./InstrumentSerif-Regular.woff2", weight: "400", style: "normal" },
    { path: "./InstrumentSerif-Italic.woff2", weight: "400", style: "italic" },
  ],
  variable: "--font-instrument-serif",
  display: "swap",
  fallback: ["Georgia", "Times New Roman", "serif"],
});

/**
 * The same faces for the guide covers on the landing page, which sit below
 * the fold: not preloaded, so they never compete with the hero's resources.
 * The browser fetches them only when the covers' text is laid out.
 */
export const instrumentSerifDeferred = localFont({
  src: [
    { path: "./InstrumentSerif-Regular.woff2", weight: "400", style: "normal" },
    { path: "./InstrumentSerif-Italic.woff2", weight: "400", style: "italic" },
  ],
  variable: "--font-instrument-serif",
  display: "swap",
  preload: false,
  fallback: ["Georgia", "Times New Roman", "serif"],
});
