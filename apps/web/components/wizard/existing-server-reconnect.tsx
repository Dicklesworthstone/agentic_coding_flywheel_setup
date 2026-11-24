"use client";

import { CommandCard } from "@/components/command-card";
import {
  buildRootSessionKeyRepairCommand,
  formatSshTarget,
  SSH_KEY_PATH_UNIX,
  SSH_PUBLIC_KEY_PATH_WINDOWS_POWERSHELL,
  SSH_KEY_PATH_WINDOWS_POWERSHELL,
} from "@/lib/commandBuilder";

export function ExistingServerReconnect({ username, host }: { username: string; host: string }) {
  const target = formatSshTarget(username, host);
  const ssh = "ssh -o IdentitiesOnly=yes -o PreferredAuthentications=publickey -i";
  return (
    <section className="space-y-4">
      <h2 className="text-xl font-semibold">Test the new login in a second terminal</h2>
      <p>
        Keep your working admin session open. On your laptop, open another terminal and
        test the dedicated ACFS key for <strong>{username}</strong>.
      </p>
      <CommandCard
        command={`${ssh} ${SSH_KEY_PATH_UNIX} ${target}`}
        windowsCommand={`${ssh} ${SSH_KEY_PATH_WINDOWS_POWERSHELL} ${target}`}
        description={`Connect to the VPS as ${username} with the ACFS key`}
        runLocation="local"
      />
      <details className="space-y-3 rounded-md border p-4">
        <summary className="cursor-pointer font-medium">If SSH says permission denied</summary>
        <p>
          A sudo admin&apos;s existing key may belong to a different account. In your
          original root shell, run the command below. It waits for one public key.
        </p>
        <CommandCard
          command={buildRootSessionKeyRepairCommand(username)}
          description={`Authorize the ACFS public key for ${username}`}
          runLocation="vps"
        />
        <p>
          On the laptop, display the public key. Copy the complete output line, paste it
          into the waiting root shell and press Enter. Retry the login in your second terminal.
        </p>
        <CommandCard
          command="cat ~/.ssh/acfs_ed25519.pub"
          windowsCommand={`Get-Content ${SSH_PUBLIC_KEY_PATH_WINDOWS_POWERSHELL}`}
          description="Display the public key on your laptop"
          runLocation="local"
        />
      </details>
      <p>After the new login succeeds, run <code>whoami</code> and check it prints <code>{username}</code>.</p>
    </section>
  );
}
