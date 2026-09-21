"use client";

import { ArrowRight, Cloud, Database, Globe, Key, Rocket } from "lucide-react";
import {
  CodeBlock,
  Divider,
  FeatureCard,
  FeatureGrid,
  GoalBanner,
  Highlight,
  InlineCode,
  Paragraph,
  Section,
  TipBox,
} from "./lesson-components";

export function CloudInfraLesson() {
  return (
    <div className="space-y-8">
      <GoalBanner>
        Deploy and manage cloud infrastructure with PostgreSQL, Supabase, Vercel, and Wrangler — the
        cloud stack that powers modern web applications.
      </GoalBanner>

      {/* Your Cloud Stack */}
      <Section title="Your Cloud Stack" icon={<Cloud className="h-5 w-5" />} delay={0.1}>
        <Paragraph>
          ACFS installs CLI tools for the major <Highlight>cloud platforms</Highlight> used in
          modern web development. From local databases to edge computing, everything is configured
          and ready to go.
        </Paragraph>

        <div className="mt-6">
          <FeatureGrid>
            <FeatureCard
              icon={<Database className="h-5 w-5" />}
              title="PostgreSQL 18"
              description="Production database with JSONB, full-text search"
              gradient="from-sky-500/20 to-blue-500/20"
            />
            <FeatureCard
              icon={<Key className="h-5 w-5" />}
              title="Supabase"
              description="Auth, real-time, storage — Firebase alternative"
              gradient="from-emerald-500/20 to-teal-500/20"
            />
            <FeatureCard
              icon={<Rocket className="h-5 w-5" />}
              title="Vercel"
              description="Deploy Next.js with zero config"
              gradient="from-violet-500/20 to-purple-500/20"
            />
            <FeatureCard
              icon={<Globe className="h-5 w-5" />}
              title="Wrangler"
              description="Cloudflare Workers, R2, D1 at the edge"
              gradient="from-amber-500/20 to-orange-500/20"
            />
          </FeatureGrid>
        </div>
      </Section>

      <Divider />

      {/* PostgreSQL 18 */}
      <Section title="PostgreSQL 18" icon={<Database className="h-5 w-5" />} delay={0.15}>
        <Paragraph>
          Local database for development, testing, and direct production use.
          <Highlight>PostgreSQL 18</Highlight> gives you JSONB document storage, full-text search,
          and row-level security out of the box.
        </Paragraph>

        <div className="mt-6">
          <CodeBlock
            code={`# Check PostgreSQL status
sudo systemctl status postgresql

# Connect to local database
psql -U postgres

# Create a database for your project
createdb myproject

# Common psql commands
\\l          -- List databases
\\dt         -- List tables
\\d+ table   -- Describe table with details
\\q          -- Quit

# Run SQL from command line
psql -U postgres -d myproject -c "SELECT version();"

# Dump a database
pg_dump myproject > backup.sql

# Restore from dump
psql -U postgres -d myproject < backup.sql

# PostgreSQL 18 features
# - JSONB for document storage
# - Full-text search built in
# - Row-level security (RLS) for multi-tenant`}
            language="bash"
            showLineNumbers
          />
        </div>

        <div className="mt-6">
          <TipBox variant="tip">
            PostgreSQL runs locally on your VPS. For production, use Supabase (managed PostgreSQL
            with auth and real-time) or connect to a cloud instance.
          </TipBox>
        </div>
      </Section>

      <Divider />

      {/* Supabase CLI */}
      <Section title="Supabase CLI" icon={<Key className="h-5 w-5" />} delay={0.2}>
        <Paragraph>
          <Highlight>Backend-as-a-service</Highlight> with auth, database, storage, and real-time —
          all managed through the Supabase CLI.
        </Paragraph>

        <div className="mt-6">
          <CodeBlock
            code={`# Headless VPS auth: create an access token in the browser first
export SUPABASE_ACCESS_TOKEN="your-token-here"
supabase login --token "$SUPABASE_ACCESS_TOKEN"

# Initialize in your project
supabase init

# Link to a remote project
supabase link --project-ref <ref>

# Start local development stack
supabase start
# → Starts local Postgres, Auth, Storage, Realtime

# Run migrations
supabase db push

# Generate TypeScript types from schema
supabase gen types typescript --linked > types/supabase.ts

# Pull remote schema changes
supabase db pull

# Reset local database
supabase db reset

# Check project status
supabase status`}
            language="bash"
            showLineNumbers
          />
        </div>

        <div className="mt-6">
          <TipBox variant="warning">
            On a headless VPS, don&apos;t rely on browser OAuth. Create the token on your laptop
            first, then authenticate with <InlineCode>supabase login --token ...</InlineCode> or
            export <InlineCode>SUPABASE_ACCESS_TOKEN</InlineCode> for later commands.
          </TipBox>
        </div>

        <div className="mt-6">
          <TipBox variant="tip">
            <InlineCode>supabase gen types</InlineCode> generates TypeScript types from your
            database schema. Run it after every migration to keep your types in sync.
          </TipBox>
        </div>
      </Section>

      <Divider />

      {/* Vercel CLI */}
      <Section title="Vercel CLI" icon={<Rocket className="h-5 w-5" />} delay={0.25}>
        <Paragraph>
          Deploy <Highlight>Next.js apps</Highlight> with zero configuration. Vercel handles builds,
          CDN, serverless functions, and preview deployments automatically.
        </Paragraph>

        <div className="mt-6">
          <CodeBlock
            code={`# Headless VPS auth: start the device flow from the VPS
vercel login

# Deploy current directory
vercel

# Deploy to production
vercel --prod

# Link to existing project
vercel link

# Pull environment variables
vercel env pull .env.local

# List deployments
vercel ls

# View deployment logs
vercel logs <url>

# Set environment variables
vercel env add STRIPE_KEY production

# Preview deployment (creates unique URL)
vercel --prebuilt`}
            language="bash"
            showLineNumbers
          />
        </div>

        <div className="mt-6">
          <TipBox variant="warning">
            <InlineCode>vercel login</InlineCode> now supports a device-login flow on headless
            terminals. Use <InlineCode>VERCEL_TOKEN</InlineCode> only when you specifically need
            non-interactive automation or CI auth.
          </TipBox>
        </div>

        <div className="mt-6">
          <TipBox variant="tip">
            Vercel automatically detects Next.js projects. Just run <InlineCode>vercel</InlineCode>{" "}
            and it handles the build configuration. Use <InlineCode>vercel --prod</InlineCode> for
            production deployments.
          </TipBox>
        </div>
      </Section>

      <Divider />

      {/* Wrangler (Cloudflare) */}
      <Section title="Wrangler (Cloudflare)" icon={<Globe className="h-5 w-5" />} delay={0.3}>
        <Paragraph>
          <Highlight>Cloudflare Workers</Highlight>, R2 object storage, D1 database, and KV store —
          deploy serverless code to the edge in seconds.
        </Paragraph>

        <div className="mt-6">
          <CodeBlock
            code={`# Headless VPS auth: create a Cloudflare API token in the browser first
export CLOUDFLARE_API_TOKEN="your-token-here"
export CLOUDFLARE_ACCOUNT_ID="your-account-id"
wrangler whoami

# Initialize a Worker project
wrangler init my-worker

# Run Worker locally
wrangler dev

# Deploy to Cloudflare
wrangler deploy

# Manage KV namespaces
wrangler kv namespace list
wrangler kv key put --namespace-id <id> "key" "value"

# R2 object storage
wrangler r2 bucket list
wrangler r2 object put my-bucket/file.txt --file ./file.txt

# D1 database
wrangler d1 list
wrangler d1 execute my-db --command "SELECT * FROM users"

# Tail production logs
wrangler tail`}
            language="bash"
            showLineNumbers
          />
        </div>

        <div className="mt-6">
          <TipBox variant="warning">
            <InlineCode>wrangler login</InlineCode> expects a browser session. On a headless VPS,
            use <InlineCode>CLOUDFLARE_API_TOKEN</InlineCode> instead, and add{" "}
            <InlineCode>CLOUDFLARE_ACCOUNT_ID</InlineCode> for workflows that need an explicit
            account.
          </TipBox>
        </div>
      </Section>

      <Divider />

      {/* The Deployment Pipeline */}
      <Section
        title="The Deployment Pipeline"
        icon={<ArrowRight className="h-5 w-5" />}
        delay={0.35}
      >
        <Paragraph>
          How these tools work together in practice — from local development to production
          deployment:
        </Paragraph>

        <div className="mt-6 grid gap-4 sm:grid-cols-2">
          <div className="rounded-lg border border-blue-500/20 bg-blue-500/5 p-4">
            <div className="mb-2 text-sm font-semibold text-blue-400">Step 1: Local Dev</div>
            <p className="text-sm text-zinc-400">
              PostgreSQL + Supabase local stack for development
            </p>
          </div>
          <div className="rounded-lg border border-violet-500/20 bg-violet-500/5 p-4">
            <div className="mb-2 text-sm font-semibold text-violet-400">Step 2: Testing</div>
            <p className="text-sm text-zinc-400">Run against local database, generate types</p>
          </div>
          <div className="rounded-lg border border-emerald-500/20 bg-emerald-500/5 p-4">
            <div className="mb-2 text-sm font-semibold text-emerald-400">Step 3: Deploy App</div>
            <p className="text-sm text-zinc-400">Vercel deploys Next.js frontend</p>
          </div>
          <div className="rounded-lg border border-amber-500/20 bg-amber-500/5 p-4">
            <div className="mb-2 text-sm font-semibold text-amber-400">Step 4: Edge Logic</div>
            <p className="text-sm text-zinc-400">
              Wrangler deploys API routes to Cloudflare Workers
            </p>
          </div>
        </div>

        <div className="mt-6">
          <TipBox variant="info">
            Local PostgreSQL for development, Supabase for managed backend, Vercel for frontend
            deployment, and Wrangler for edge computing. The full cloud stack.
          </TipBox>
        </div>
      </Section>
    </div>
  );
}
