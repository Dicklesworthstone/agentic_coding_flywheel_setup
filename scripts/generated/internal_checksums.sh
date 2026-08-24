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
  [install.sh]="47e9b1ce139891531aadc975c0f9b213311e995dd60de0d4a20888288f59cd88"
  [checksums.yaml]="a62d703fe6d1953b22db8db249538c8a29eff8955f6e555ca4472fb2ee00a0e3"
  [scripts/preflight.sh]="6c49cbb7368c52cbfb720b2781e1b335379a88e151ce24a5b386e9b91b99273c"
  [scripts/lib/security.sh]="f7083dc6e8a21f6406b07efa56e9bb7a708b1d2c560c702cadca396575fedaa4"
  [scripts/lib/github_api.sh]="80699922df2e924694f5682457e614dedf9181d7c071472cc8a6db4f17373d3d"
  [scripts/lib/contract.sh]="22c148f44ddbaccd559196196ef903f26f65fc77e3b1b6b4efc62b77d3b97aa3"
  [scripts/lib/agents.sh]="d8cfa821bd712ddd07b9c40a9f43edb90170526d112c2c8fad43ba4d9c5b3918"
  [scripts/lib/update.sh]="a01439b7b074c3ef50e6ca8e3b6ca53a460ab6a00faa103699b7a70d84110328"
  [scripts/lib/doctor.sh]="3945612300deb7c962e0e0ec14f06371650a4c608f3d32ca819ea5af91a9e96c"
  [scripts/lib/acfs-services.sh]="d4fbfcb6cce3cba3f266c72df4f9dee562f03f9563f457dca3194ed22db7adc7"
  [scripts/lib/doctor_fix.sh]="0a11a8df59b119a22f5a9d9734897be8a66d8cff71f9857a71a886f3b26a250b"
  [scripts/lib/offline_artifact_pack.sh]="38eac1731c1354772a67349d50013cd7c9d5bb4c52f6a2be7d85b74fd8e2d6ba"
  [scripts/lib/autofix.sh]="6ac5756ccc308c18383cfe78b2e75806ab722789ff10977e194599231f65cc92"
  [scripts/lib/autofix_existing.sh]="5cbfc0e4051c30d9a52268b7cd5c1940089579fe5e2495d4da22ed609a05044f"
  [scripts/lib/autofix_unattended.sh]="848f5744f75503eebe422a9d2418ed6b1341cfd6452004ee0a4e902d04f5d94a"
  [scripts/lib/autofix_version_managers.sh]="e235b7bfb95115f00bf7a4e3398be504c576d1fbe97a64c64a988294d62d621e"
  [scripts/lib/ubuntu_upgrade.sh]="e33b9d62f3ff3843b308a759da841259cf1877f4f9d5651a856d604eadc58753"
  [scripts/lib/upgrade_resume.sh]="087c0d6470a6026ea4053f98d3a2d3255c70fae3c8c5ca80feccb8bcbf80539b"
  [scripts/lib/install_helpers.sh]="3fded81a25b72b665842b8a834a3bc25fb906ef992f225fac45bb6a4a46a2d94"
  [scripts/lib/logging.sh]="890d8e6e44332bede591e462b277a903ae8d8679adebd8cc4fc76face078f6be"
  [scripts/lib/output.sh]="95c83ae9c67fbd9364f1d69a6430ca8df7ebd1bd2cfa0fe9339afdead74e96eb"
  [scripts/lib/gum_ui.sh]="1616f7f6fdd730802da196a661a2e5f576e480e4e96d745ce12ea5b64f9559b5"
  [scripts/lib/progress.sh]="a8400b341c5581f4acd50595aeea62a5ebb3bb8c914e6bcd5569dd23a673ceca"
  [scripts/lib/state.sh]="bd1a0d06a584e4469e2b2b2a1ea485e5151cdb146e4bc8aa5f5c9b08165bf08a"
  [scripts/lib/report.sh]="aa0e2c4b279a90d4b3b87ed306500f7fd13eb26583dda6f82dc2a71f65f18a8f"
  [scripts/lib/error_tracking.sh]="e67f4b1f86c7bef48e6d898c60a064108f3b3421f35385475b17562736d12dbd"
  [scripts/lib/session.sh]="4b6f26f0400f277f62d84e7d9cd7f01540af9810aa60e273b7b17592f17d26e8"
  [scripts/lib/os_detect.sh]="5cc5c182d212d7ea76fd345f97e97d808aad5d7e8cb29736b03f88e2ad115889"
  [scripts/lib/errors.sh]="7733e51599c65d7e4f38ffa38a5b6833e2ba182280676bd34a63788c7f2b0adc"
  [scripts/lib/user.sh]="fc079920a34237bac37d3fb7107f3f8c8ae9e84d82a123669b5eef5d23f68dfe"
  [scripts/lib/tools.sh]="b8490b07a8d0b63dfa55968d250e9ecce6c19acb1093368269e285a6f6938376"
  [scripts/lib/tailscale.sh]="a9370fb4ec1844997bd21d79d4647f9113e8c2c30c1b670be699eedf3f9ac049"
  [scripts/lib/webhook.sh]="603388d4fbd038b5500c10823175e594c8e7629157376b07af829b5e995483d7"
  [scripts/lib/notify.sh]="ac8a474c654a48f24dfe5da0a193ed45355d9b1d92948c08b33f5a1b83e64b76"
  [scripts/lib/stack.sh]="0d211dbc191e7f956955ef2e0b0b0382c6b95c45228c9c14a6d178b1178f5e43"
  [scripts/lib/export-config.sh]="6280123436223b5708f506b0a18b83c64891f8ee55af93c5c513f7fb202b97e3"
  [scripts/acfs-global]="71067648b4f6cdb5fe4be781f2ed08658a701905d5ab06a57f4cd8be45821430"
  [scripts/acfs-update]="178ab5f2af97f8c1584aa298aef350b28fe5b8dafd95e85c28af3be27e05f816"
  [scripts/lib/nightly_update.sh]="24e3352a5462440d540109a0f75860ba1277f3bb007a0f7a4623f6889d9d453c"
  [scripts/templates/acfs-upgrade-resume.service]="301dcd9e668e25c7d3327eaa6935848fd9a330e4e1c5b7928bd028447441a6b0"
  [scripts/templates/acfs-nightly-update.service]="9c9354412c770faf7ab39b68cdb35f5d5313ab022128d0561e12c98b0a53ce86"
  [scripts/templates/acfs-nightly-update.timer]="aa4fbad4fadabe0b61d202b4bf4311ce71c1132ad0ce8453099b593aa04988c3"
  [packages/onboard/onboard.sh]="046fa49c9d5dbb08471accbfccf6e8bdd1e3e22033759bfe56f550212044b539"
  [scripts/generated/manifest_index.sh]="b3a8476f7d9c151f6c8fe2bc165325bf3b905ae73484ebaa68d5046c54a7aab5"
  [scripts/generated/doctor_checks.sh]="41395508b9370dee70afd215819ecd27d77ea9d0e7289cd58283c2319122427c"
  [scripts/generated/install_all.sh]="30abb5805ee91ab7a5139fda21cd5c9031639f39837cb13f21255f90ac006ae7"
  [scripts/generated/install_base.sh]="492bed92b4ad52fa2cd2d2289ba87230f8654f3a3014ef1d8ac28e58d587a8c1"
  [scripts/generated/install_users.sh]="b90a4abab9dd9414ccfcac98ef4c09c57dc96950294a469bd58e984b4a68826c"
  [scripts/generated/install_filesystem.sh]="85b6b2d01cb2fe0c24514f6667bb332931fffb60118c6f990b322aae6c27d7ac"
  [scripts/generated/install_shell.sh]="f324da4b209139fadb13ce9d5728a8829d34424a87a901c5aa9dd597348abc7f"
  [scripts/generated/install_cli.sh]="189995a26698dd0d61c597ab32b7b2aa7c806ce6f5d50484885c24b439df62b3"
  [scripts/generated/install_network.sh]="8da8d6a8a4b13641ecaa39adf66965e27b1f2dcb59f8c36b9d7c12552d357b7d"
  [scripts/generated/install_lang.sh]="5c7425fc312c661c79a9835a5e4f60aa97ec1caf362d1ca7fc5d0759fc540b0f"
  [scripts/generated/install_tools.sh]="607dfd500650251f08335746bf5c0809d8c87b7b584780f1515ba7e13a0b666f"
  [scripts/generated/install_db.sh]="34f6576756726dc0eaf4ceb83eedfbfdd20f565957c88e30ca123ad787c4a0d8"
  [scripts/generated/install_cloud.sh]="f459c5bd58bc49449b62da3069f8f538cbf67d9764017c848a98e8be2feaad1e"
  [scripts/generated/install_agents.sh]="089db3856eabf71813dfb4b1e7b9007f99e1d40ad2a3c66ea621e571837c58f4"
  [scripts/generated/install_stack.sh]="a1b639e8646b5cd6936677e5153fa4d6359184bdd119e736c346dbcfd60f0fab"
  [scripts/generated/install_acfs.sh]="eb3c44b04a44e79ca9c446551bb28ea35f4ba5dce17021976913102d651cd926"
)

ACFS_INTERNAL_CHECKSUMS_COUNT=59
