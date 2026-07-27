# `ParallelRunnerKit/` 開発者向けメモ

`ParallelRunnerKit/` を将来再利用可能なパッケージ (仮称 `DistributedRunner.jl`) として切り出すための設計メモ。開発者向け専用。利用者向けドキュメントは [README.ja.md](../README.ja.md)。

English: [DEVELOPMENT.md](DEVELOPMENT.md)

**動作環境:** 開発・テストは **macOS のみ**。macOS 以外の動作は検証しない。

**配布の切り分け:**
- **分散だけ足したい:** `ParallelRunnerKit/` をそのままコピーし、スクリプト契約 (`init_output_dir!`, `main()`) を満たし、`Project.toml` の `[deps]` を自分の環境にマージする。ワーカーでロードするモジュール名がルート `Project.toml` の `name` と違うなら `--package NAME` を使う。
- **シミュだけ欲しい:** `ParallelRunnerKit/` を丸ごと削除してよい。他のファイルはこの Kit を名前で参照していない。

**フォルダ名:** モジュール名・スタブ `Project.toml` の `name` と揃えて `ParallelRunnerKit` のままにする。公開先: **[daihiko-lab/ParallelRunnerKit.jl](https://github.com/daihiko-lab/ParallelRunnerKit.jl)**。`resolve_pkg_project_dir` は `name == "ParallelRunnerKit"` でスタブ判定するので、ディレクトリ名には依存しない。

## ホストアプリへの取り込み

**git サブモジュールとして:**

```bash
git clone --recurse-submodules <親リポジトリの URL>
# すでに clone 済みでサブモジュールが空のとき:
git submodule update --init --recursive
```

固定コミットを上げる: このリポジトリに push した後、`cd ParallelRunnerKit && git pull origin main && cd .. && git add ParallelRunnerKit && git commit -m "Bump ParallelRunnerKit submodule"`。

**サブモジュールなしの一回限りのミラー:** ホストアプリのルートで `git subtree split -P ParallelRunnerKit -b publish-branch` し、そのブランチをこのリポジトリの `main` に push する。`--force-with-lease` はこちらの `main` を意図的に書き換えるときだけ使う。

## ホストアプリケーションとの結合

| 場所 | 前提 |
|----------|-----------------|
| `runner.jl` | `Project.toml` の `name` (または `--package`) でワーカー側のパッケージをロード。include したスクリプトの `init_output_dir!(ARGS)` → `main()` を呼ぶ |
| `src/ParallelRunnerKit.jl` | 共有ヘルパ (パス・ログ・SSH/git・CLI パース・メモリ/git 整合チェック)。ホストパッケージを import しない |
| `setup.jl` | プロジェクトルートが `Project.toml` を持つ Julia プロジェクトであること |

どのファイルもホストアプリを名前で import していない。runner は `Project.toml` を読んでパッケージ名を発見するので、変更なしで他の Julia プロジェクトでも動く。

## インターフェース契約 (スクリプト側)

`runner.jl` で動かすスクリプトは、`Main` に次の 2 関数だけを定義する必要がある:

```julia
# ワーカー追加**前**に呼ばれる。ENV["DISTRIBUTED_OUTPUT_DIR"] を設定する必要がある。
# 結果をマスターのみに保存するなら ENV["DISTRIBUTED_SKIP_COLLECT"] = "1" も設定する。
function init_output_dir!(args::Vector{String})::String
    ...
end

# ワーカー準備完了**後**に呼ばれる。nworkers()/workers() を見て
# 並列化戦略 (pmap / remotecall / @distributed) を自分で決める。
function main()
    ...
end
```

この 2 関数の契約が `runner.jl` と実験スクリプト間の唯一の結合点。将来切り出す場合もここは安定させる。

## 切り出しの進捗

| 項目 | 状況 |
|---|---|
| 共有コードのモジュール化 | 完了 — `src/ParallelRunnerKit.jl` |
| 任意のリモート URL / パス | 完了 — `setup.jl --repo` / `--remote-path`、`DISTRIBUTED_REMOTE_PROJECT_ROOT` |
| ワーカーモジュール名の上書き | 完了 — `runner.jl --package NAME` |
| `init_output_dir!`/`main()` を公開 API として明文化 | 未着手 (軽量な abstract interface でもよい) |
| `DistributedRunner.jl` として登録 | 未着手 (研究室内利用なら未登録のままでもよい) |
| `ParallelRunnerKit/Project.toml` は持ち込み専用でアプリの環境ではない | 設計通り。スタブ名は未登録 |

## バージョン管理と再現性

- `Project.toml` の `version` は `parallel_runner_kit_version()` / `PARALLEL_RUNNER_KIT_VERSION` として公開され、`runner.jl` 起動時にログに出る。
- `runner.jl` はアプリ側プロジェクトディレクトリの git 短縮ハッシュをログに出す。
- SSH ワーカー利用時は `check_git_hashes` が完全同一コミットを要求する (`--skip-hash-check` で無効化可)。リモートルートは `DISTRIBUTED_REMOTE_PROJECT_ROOT` があればそれ、なければローカルと同じ絶対パス。
- **CI:** GitHub Actions (`.github/workflows/CI.yml`) が Julia **1.12** (カバレッジあり) と **1.13** (安定版が出るまでは prerelease チャネル) で `Pkg.test` を回す。ローカルでは `julia --project=. -e 'using Pkg; Pkg.instantiate(); Pkg.test(; coverage=false)'`。テストはモノレポ配置で `ParallelRunnerKit/Project.toml` の `[deps]` (ほぼ全て) がルート `Project.toml` に同じ UUID で載っていることも検証する。`Distributed` は Julia 同梱 stdlib のため除外。SSH / リモート探査は CI 対象外。
- **今後の候補:** バージョンと一致する git タグ + `CHANGELOG.md`、厳密な環境固定用の `Manifest.toml` コミット、`using` 後のワーカー自己申告、`--skip-hash-check` を本番では監査用限定にする運用。

## やらないこと

- シミュレーション固有のロジック (`SimulationConfig`、結果フォーマットなど) を入れない。runner はシミュレーションに中立であり続ける。
- 非 Julia ワーカーや非 SSH トランスポートはサポートしない。
- 現在のハートビート + 接続安定化待ち以上の自動リトライ/fault-tolerance は追加しない。失敗タスクの再キューは `pmap` のエラー処理がスクリプト側で担う。

## Julia 1.12+ の安定性メモ

`tunnel=true` + 多数の SSH ワーカーでは、`addprocs` が全 TCP 接続の登録完了前に return してしまうことがある。`runner.jl` は `DISTRIBUTED_INIT_DELAY_SEC` (既定 5 秒) とワーカーごとの ping リトライ (既定 6 回) で回避している。1.13 でも実機のマルチホスト実行で問題ないと確認できるまでは有効と考えてよい。
