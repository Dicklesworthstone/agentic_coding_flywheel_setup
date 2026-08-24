#!/usr/bin/env bash
# shellcheck disable=SC2034
# ============================================================
# AUTO-GENERATED internal script checksums - DO NOT EDIT
# Regenerate: bun run generate (from packages/manifest)
# ============================================================
# SHA256 checksums for checksum-controlled runtime files (bd-3tpl).
# Parsed as inert data by install.sh and used by check-manifest-drift.sh.

ACFS_INTERNAL_CHECKSUMS_SCHEMA=1

declare -gA ACFS_INTERNAL_CHECKSUMS=(
  [install.sh]="812461beecc75aa2b4481a7484996e4639267af6a69ca5184899d5d910a81632"
  [checksums.yaml]="a62d703fe6d1953b22db8db249538c8a29eff8955f6e555ca4472fb2ee00a0e3"
  [scripts/preflight.sh]="6c49cbb7368c52cbfb720b2781e1b335379a88e151ce24a5b386e9b91b99273c"
  [scripts/lib/security.sh]="792e033fa3f397ca30307d5cc99d0fa2b6489258f1c17fe8d83604e765640733"
  [scripts/lib/github_api.sh]="80699922df2e924694f5682457e614dedf9181d7c071472cc8a6db4f17373d3d"
  [scripts/lib/contract.sh]="22c148f44ddbaccd559196196ef903f26f65fc77e3b1b6b4efc62b77d3b97aa3"
  [scripts/lib/agents.sh]="1762cbb606a079ecef7b54465feb1a2a5e99a07aa0d93f5b1c333a31077761e4"
  [scripts/lib/update.sh]="ca8a693169936926018d1fb774f4d7dfa8ba41c9035de534d9725747990d6a0d"
  [scripts/lib/doctor.sh]="327027c108b6cd6e16fea9c8b897da252ed29b941da86f21a9b7a328f6d83b3f"
  [scripts/lib/acfs-services.sh]="d4fbfcb6cce3cba3f266c72df4f9dee562f03f9563f457dca3194ed22db7adc7"
  [scripts/lib/doctor_fix.sh]="b5e7a73779aa965bdab0a1f2937cad38604a63f80de45deb67f243456c881a0c"
  [scripts/lib/offline_artifact_pack.sh]="29ede68755c85a54bc32765bf52acfc59047c8a7d15569be6db424987731d9b4"
  [scripts/lib/autofix.sh]="41ee24341d9f6ea2f45e5dd75d8ca2ef9703d862b728e9bb6ab8da6d5ffb7131"
  [scripts/lib/autofix_existing.sh]="5cbfc0e4051c30d9a52268b7cd5c1940089579fe5e2495d4da22ed609a05044f"
  [scripts/lib/autofix_unattended.sh]="848f5744f75503eebe422a9d2418ed6b1341cfd6452004ee0a4e902d04f5d94a"
  [scripts/lib/autofix_version_managers.sh]="e235b7bfb95115f00bf7a4e3398be504c576d1fbe97a64c64a988294d62d621e"
  [scripts/lib/ubuntu_upgrade.sh]="501224178bae574971822ecc6cc4fdb33b90e5a6e8b37635ee61626744126425"
  [scripts/lib/upgrade_resume.sh]="087c0d6470a6026ea4053f98d3a2d3255c70fae3c8c5ca80feccb8bcbf80539b"
  [scripts/lib/install_helpers.sh]="0bf42cfdc91050051d322157ee00cc116fac547a1ed36b373bc2546ee7af1a88"
  [scripts/lib/logging.sh]="890d8e6e44332bede591e462b277a903ae8d8679adebd8cc4fc76face078f6be"
  [scripts/lib/output.sh]="95c83ae9c67fbd9364f1d69a6430ca8df7ebd1bd2cfa0fe9339afdead74e96eb"
  [scripts/lib/gum_ui.sh]="1616f7f6fdd730802da196a661a2e5f576e480e4e96d745ce12ea5b64f9559b5"
  [scripts/lib/progress.sh]="a8400b341c5581f4acd50595aeea62a5ebb3bb8c914e6bcd5569dd23a673ceca"
  [scripts/lib/state.sh]="c829c5656d03f4d0a055874533fdcee3e5f3f20d3fab16c7d692bd33daa50c8f"
  [scripts/lib/report.sh]="15c7aa11eb807742584433ff50be1f1b0bdacc01b8b35f39a032e298da21c24a"
  [scripts/lib/error_tracking.sh]="5296ebc3428ece8912b1fbc29a576dba8e5789b6a62f3efdb68b497ae106c007"
  [scripts/lib/session.sh]="8a2ab64a67006c62ac0db8d89ea6d71d160f3f2efd2cb99ffe6ea0857abde3e5"
  [scripts/lib/os_detect.sh]="5cc5c182d212d7ea76fd345f97e97d808aad5d7e8cb29736b03f88e2ad115889"
  [scripts/lib/errors.sh]="7733e51599c65d7e4f38ffa38a5b6833e2ba182280676bd34a63788c7f2b0adc"
  [scripts/lib/user.sh]="fc079920a34237bac37d3fb7107f3f8c8ae9e84d82a123669b5eef5d23f68dfe"
  [scripts/lib/tools.sh]="e2d48e800888b759245e66cc9d86d097d83bf10f6d3bd2fcd17ec4bddfec94e0"
  [scripts/lib/tailscale.sh]="a9370fb4ec1844997bd21d79d4647f9113e8c2c30c1b670be699eedf3f9ac049"
  [scripts/lib/webhook.sh]="603388d4fbd038b5500c10823175e594c8e7629157376b07af829b5e995483d7"
  [scripts/lib/notify.sh]="ac8a474c654a48f24dfe5da0a193ed45355d9b1d92948c08b33f5a1b83e64b76"
  [scripts/lib/stack.sh]="6754693d8b98733c2d8361214624cad0c94a8fd971311e2aa1d4087c1efcdab2"
  [scripts/lib/export-config.sh]="6280123436223b5708f506b0a18b83c64891f8ee55af93c5c513f7fb202b97e3"
  [scripts/acfs-global]="71067648b4f6cdb5fe4be781f2ed08658a701905d5ab06a57f4cd8be45821430"
  [scripts/acfs-update]="178ab5f2af97f8c1584aa298aef350b28fe5b8dafd95e85c28af3be27e05f816"
  [scripts/lib/nightly_update.sh]="fa753f048bbfcfda265d30e3435a604c0169eed30a78b7191a1b9790f101364f"
  [scripts/templates/acfs-upgrade-resume.service]="301dcd9e668e25c7d3327eaa6935848fd9a330e4e1c5b7928bd028447441a6b0"
  [scripts/templates/acfs-nightly-update.service]="9c9354412c770faf7ab39b68cdb35f5d5313ab022128d0561e12c98b0a53ce86"
  [scripts/templates/acfs-nightly-update.timer]="aa4fbad4fadabe0b61d202b4bf4311ce71c1132ad0ce8453099b593aa04988c3"
  [packages/onboard/onboard.sh]="90921cfbf03b4d18594ae715d7f5ec2d2a919406d284bd69d6983c9f32356c2e"
  [scripts/generated/manifest_index.sh]="7ca745d1715cdb24e362e3f4da2a2c2ee0b37f4d93c3bf0ae9d7a774514026a5"
  [scripts/generated/doctor_checks.sh]="9b4cc70aa706504c76f69e9cb7abfb732f31c31f170547c061058a7986025c07"
  [scripts/generated/install_all.sh]="e08b9d738fbb8d894ffe46b1ae9d48dbb2364e4fcaf073c10ab5e446bb9dfd5b"
  [scripts/generated/install_base.sh]="8c33ebb4be69f8ead3cb225723da361ea1ab16c6ef884471b6f1665d28cd4586"
  [scripts/generated/install_users.sh]="8d7c47770bd6fd74262ebeef00dae865c70f770fdbb49daf2f51bdb6cf8a28ef"
  [scripts/generated/install_filesystem.sh]="7f1436db2d6371f6a040645b89afaa936063a2312dead366551e818a538adfca"
  [scripts/generated/install_shell.sh]="1e515211e22b748cd1a209aefa40180fef0067c82ab62dbd7b02731b8371f5a3"
  [scripts/generated/install_cli.sh]="2c892b3e74015d4ade0c5e55d9b1acb6608642d978b9b315acd63d543aa7cd48"
  [scripts/generated/install_network.sh]="0c521e91d2c9b5380b777fbd031f0612b969ecd9c76d46ed09e732eb2bbab843"
  [scripts/generated/install_lang.sh]="65c9dc98821e2192b1bde494c95976864d80c48f74ed3abe7df01f7dd3c1b9e2"
  [scripts/generated/install_tools.sh]="8affa31db7df156cf9f2e2af9ea44c9d5949ca0a78cee769de5de132a4756daf"
  [scripts/generated/install_db.sh]="a3686ab9c5acd1d1d3f257e571f3c390166372092742b20bb41dba9b16ae4395"
  [scripts/generated/install_cloud.sh]="c7241208c13f459d70df0393bdbc7e47ee4ecb54374c10261bf4d76083bba8bc"
  [scripts/generated/install_agents.sh]="35170a18ec92ecf8010950052c91c97e86f6db28b92fbaa2c662ea6ee3be7e9f"
  [scripts/generated/install_stack.sh]="4961bd83b6af74f019f1b2ec50f93c826ed8dbedbe8a79a869a5eb15a2505b22"
  [scripts/generated/install_acfs.sh]="6c8a36b2f813560b49759bdbb5c4b9f8b8b9f07e34ff9a3a59edfc1f3e1bbe5e"
)

ACFS_INTERNAL_CHECKSUMS_COUNT=59
