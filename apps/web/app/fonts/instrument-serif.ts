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
