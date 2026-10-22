This is a [Next.js](https://nextjs.org) project bootstrapped with [`create-next-app`](https://nextjs.org/docs/app/api-reference/cli/create-next-app).

## Getting Started

First, run the development server:

```bash
bun install
bun run dev
```

Open [http://localhost:3000](http://localhost:3000) with your browser to see the result.

You can start editing the page by modifying `app/page.tsx`. The page auto-updates as you edit the file.

Typography uses local variable fonts through `next/font/local`, so production
builds do not need to contact Google Fonts. Instrument Sans (weights 400–700)
and JetBrains Mono (100–800) retain the existing CSS variables, normal style,
preloading and swap behavior.

The two unmodified, full-coverage WOFF2 files total 202,456 bytes. They include
more glyphs than the Latin subsets previously preloaded from Google, so the
initial font payload is larger; no character coverage is intentionally dropped.
Their SIL Open Font License notices are kept beside them in `app/fonts`.
Upstream sources are pinned to these revisions:

- [Instrument Sans](https://github.com/Instrument/instrument-sans/tree/7fa22308a3d0c94ee2b3cd537a1196b65db34a3e/fonts/webfonts)
- [JetBrains Mono](https://github.com/JetBrains/JetBrainsMono/tree/19371302b95d218af43299bce79ddbddd0bc364d/fonts/webfonts)

## Learn More

To learn more about Next.js, take a look at the following resources:

- [Next.js Documentation](https://nextjs.org/docs) - learn about Next.js features and API.
- [Learn Next.js](https://nextjs.org/learn) - an interactive Next.js tutorial.

## Deploy on Vercel

The easiest way to deploy your Next.js app is to use the [Vercel Platform](https://vercel.com/new?utm_medium=default-template&filter=next.js&utm_source=create-next-app&utm_campaign=create-next-app-readme) from the creators of Next.js.

Check out our [Next.js deployment documentation](https://nextjs.org/docs/app/building-your-application/deploying) for more details.
