import { describe, expect, test } from "bun:test";
import { buildCommands, buildInstallCommand, buildShareURL } from "./commandBuilder";

describe("buildInstallCommand", () => {
  test("omits TARGET_USER for the default ubuntu user", () => {
    const command = buildInstallCommand("vibe", null, "ubuntu");

    expect(command).not.toContain("TARGET_USER=");
    expect(command).toContain("--mode vibe");
  });

  test("includes TARGET_USER and --ref for a customized install", () => {
    const command = buildInstallCommand("safe", "v1.2.3", "admin");

    expect(command).toContain('TARGET_USER="admin"');
    expect(command).toContain('--ref "v1.2.3"');
    expect(command).toContain("/v1.2.3/install.sh");
    expect(command).toContain("--mode safe");
  });

  test("omits TARGET_USER when the username does not match the installer contract", () => {
    const command = buildInstallCommand("vibe", null, "Admin");

    expect(command).not.toContain("TARGET_USER=");
    expect(command).not.toContain("Admin");
  });
});

describe("buildCommands", () => {
  test("propagates the customized username into installer and SSH commands", () => {
    const commands = buildCommands({
      ip: "10.20.30.40",
      os: "windows",
      username: "admin",
      mode: "safe",
      ref: null,
    });

    const installer = commands.find((command) => command.id === "installer");
    const sshUser = commands.find((command) => command.id === "ssh-user");

    expect(installer?.command).toContain('TARGET_USER="admin"');
    expect(sshUser?.command).toContain("admin@10.20.30.40");
    expect(sshUser?.windowsCommand).toBe("ssh -i $HOME\\.ssh\\acfs_ed25519 admin@10.20.30.40");
  });

  test("falls back to ubuntu when the username input is invalid", () => {
    const commands = buildCommands({
      ip: "10.20.30.40",
      os: "mac",
      username: "bad user",
      mode: "vibe",
      ref: null,
    });

    const installer = commands.find((command) => command.id === "installer");
    const sshUser = commands.find((command) => command.id === "ssh-user");

    expect(installer?.command).not.toContain("TARGET_USER=");
    expect(sshUser?.label).toBe("SSH as ubuntu");
    expect(sshUser?.command).toContain("ubuntu@10.20.30.40");
  });

  test("accepts lowercase usernames with dots and hyphens", () => {
    const commands = buildCommands({
      ip: "10.20.30.40",
      os: "linux",
      username: "dev-user.1",
      mode: "vibe",
      ref: null,
    });

    const installer = commands.find((command) => command.id === "installer");
    const sshUser = commands.find((command) => command.id === "ssh-user");

    expect(installer?.command).toContain('TARGET_USER="dev-user.1"');
    expect(sshUser?.label).toBe("SSH as dev-user.1");
    expect(sshUser?.command).toContain("dev-user.1@10.20.30.40");
  });
});

describe("buildShareURL", () => {
  test("drops unrelated query params from the current page URL", () => {
    const originalWindow = globalThis.window;

    Object.defineProperty(globalThis, "window", {
      value: {
        location: {
          href: "https://acfs.dev/wizard/launch-onboarding?utm_source=share",
          origin: "https://acfs.dev",
          pathname: "/wizard/launch-onboarding",
        },
      },
      configurable: true,
    });

    try {
      const shareURL = buildShareURL({
        ip: "10.20.30.40",
        os: "mac",
        username: "ubuntu",
        mode: "vibe",
        ref: null,
      });

      expect(shareURL).toBe("https://acfs.dev/wizard/launch-onboarding?ip=10.20.30.40&os=mac&mode=vibe");
      expect(shareURL).not.toContain("utm_source=");
    } finally {
      Object.defineProperty(globalThis, "window", {
        value: originalWindow,
        configurable: true,
      });
    }
  });

  test("drops usernames that the installer would reject", () => {
    const originalWindow = globalThis.window;

    Object.defineProperty(globalThis, "window", {
      value: {
        location: {
          href: "https://acfs.dev/wizard/launch-onboarding",
          origin: "https://acfs.dev",
          pathname: "/wizard/launch-onboarding",
        },
      },
      configurable: true,
    });

    try {
      const shareURL = buildShareURL({
        ip: "10.20.30.40",
        os: "linux",
        username: "Admin",
        mode: "safe",
        ref: null,
      });

      expect(shareURL).toBe("https://acfs.dev/wizard/launch-onboarding?ip=10.20.30.40&os=linux&mode=safe");
    } finally {
      Object.defineProperty(globalThis, "window", {
        value: originalWindow,
        configurable: true,
      });
    }
  });
});
