import { CLOUD_AGENTS } from "@/lib/claude-code-web";
import { getCloudAgentSetupInstructions } from "@/lib/cloud-agent-walkthroughs";

/** The public brief is the exact text used by the illustrated guide's copy action. */
export function GET(request: Request): Response {
  const selectors = new URL(request.url).searchParams.getAll("agent");
  const agentId = selectors.length === 0 ? "claude" : selectors[0];
  const agent = CLOUD_AGENTS.find((item) => item.id === agentId);
  if (selectors.length > 1 || !agent) {
    return new Response(`Choose one agent: ${CLOUD_AGENTS.map((agent) => agent.id).join(", ")}.\n`, {
      status: 400,
      headers: {
        "Content-Type": "text/plain; charset=utf-8",
        "Cache-Control": "no-store",
        "X-Content-Type-Options": "nosniff",
      },
    });
  }

  return new Response(getCloudAgentSetupInstructions(agent.id), {
    headers: {
      "Content-Type": "text/markdown; charset=utf-8",
      "Content-Disposition": 'inline; filename="acfs-cloud-agents.md"',
      "Cache-Control": "public, max-age=300",
      "X-Content-Type-Options": "nosniff",
    },
  });
}
