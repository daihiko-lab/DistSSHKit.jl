# ParallelRunnerKit.jl

[![CI](https://github.com/daihiko-lab/ParallelRunnerKit.jl/actions/workflows/CI.yml/badge.svg)](https://github.com/daihiko-lab/ParallelRunnerKit.jl/actions/workflows/CI.yml)
[![codecov](https://codecov.io/gh/daihiko-lab/ParallelRunnerKit.jl/graph/badge.svg)](https://codecov.io/gh/daihiko-lab/ParallelRunnerKit.jl)
[![Julia 1.12+](https://img.shields.io/badge/Julia-1.12+-blue.svg)](https://julialang.org/)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)

任意の Julia ドライバスクリプトを、ローカル/SSH リモートのプロセスに分散実行する (Distributed.jl。マルチスレッドではない)。

English: [README.md](README.md)

**状態:** `0.x` (1.0 未満)。マイナー版の間でもインターフェースが変わる可能性がある。

リモートホストを使う場合は、手順の前に [環境・SSH の基準](#環境ssh-の基準) を読むこと。生成AIの利用については [生成AIを用いた開発](#生成aiを用いた開発) を参照。

## 使い方は2つだけ

1. パッケージアプリ (実験的): [Pkg Apps](https://pkgdocs.julialang.org/v1/apps/) で `prunner` / `psetup` / `psuggest` を使う。キットはリポジトリに置かない。[手順](#1-パッケージアプリインストール-実験的)
2. CLI (推奨): clone/submodule した `runner.jl` 等を `julia --project=.` で実行する。[手順](#2-cli-スクリプト)

どちらもアプリルート (`Project.toml` があるディレクトリ) で動かす。

## 共通: ドライバスクリプト

分散実行の対象になる Julia スクリプトは、`Main` に次の 2 関数だけを定義する (1/2 どちらでも同じ):

```julia
# ワーカー追加前に呼ばれる。ENV["DISTRIBUTED_OUTPUT_DIR"] を設定する。
function init_output_dir!(args::Vector{String})::String
    ...
end

# ワーカー準備後に呼ばれる。nworkers()/workers() を見て pmap 等を使う。
function main()
    ...
end
```

動く最小例: [`templates/script_template.jl`](templates/script_template.jl)。

## 1. パッケージアプリインストール (実験的)

> 実験的: [Pkg Apps](https://pkgdocs.julialang.org/v1/apps/) は Julia 1.12 でまだ実験的機能。`ParallelRunnerKit` をパッケージとして入れ、`prunner` / `psetup` / `psuggest` を `~/.julia/bin` に登録する方式。アプリのリポジトリにキットを置かないのが 2 との違い。

### インストール (一度だけ)

```bash
# ローカル開発中
julia -e 'using Pkg; Pkg.Apps.develop(path="/path/to/ParallelRunnerKit.jl")'

# リリース済みコミットから
# julia -e 'using Pkg; Pkg.Apps.add(url="https://github.com/daihiko-lab/ParallelRunnerKit.jl.git")'

export PATH="$HOME/.julia/bin:$PATH"   # .zshrc 等に恒久化
prunner --help
```

| コマンド | 2 のスクリプト相当 | 用途 |
|----------|-------------------|------|
| `prunner` | `runner.jl` | 分散実行 |
| `psetup` | `setup.jl` | clone / sync / cleanup |
| `psuggest` | `suggest_workers.jl` | ワーカー数の目安 |

### 実行例

`cd` 先は自分の `MyApp.jl/` (キットの clone 先ではない):

```bash
cd ~/projects/MyApp.jl
julia --project=. -e 'using Pkg; Pkg.instantiate()'

psetup --clone HOST1 HOST2 ...
psetup --instantiate HOST1 HOST2 ...
psetup --sync HOST1 HOST2 ...
prunner --local N HOST1:W HOST2:W ... scripts/jobs.jl [args...]
psuggest --local HOST1 HOST2
```

- `julia --project=.` で runner を包む必要はない。カレントディレクトリがプロジェクトルート。
- 別パスなら `export DISTRIBUTED_PROJECT_ROOT=/path/to/MyApp.jl`。

## 2. CLI (スクリプト)

`runner.jl` / `setup.jl` / `suggest_workers.jl` を `julia --project=.` 付きで呼ぶ。キットの `.jl` ファイルがプロジェクトから参照できる必要がある (clone または submodule)。安定運用向け。

### 2-a. 自分のアプリに置く (一般的)

```bash
cd MyApp.jl
git submodule add https://github.com/daihiko-lab/ParallelRunnerKit.jl.git ParallelRunnerKit
julia --project=. -e 'using Pkg; Pkg.develop(path="ParallelRunnerKit")'
```

`Pkg.develop(path=...)` で `MyApp.jl/Project.toml` に `ParallelRunnerKit` が `[deps]` + `[sources]` として登録され、`ArgParse` / `JSON3` などキットの依存も自動で解決される。`[deps]` を手でコピーする必要はない (`Distributed` / `Dates` は stdlib なのでそもそも不要)。

`MyApp.jl/` にいることを確認してから:

```bash
# リモート準備 (初回)
julia --project=. ParallelRunnerKit/src/setup.jl --clone HOST1 HOST2 ...
julia --project=. ParallelRunnerKit/src/setup.jl --instantiate HOST1 HOST2 ...

# コード同期
julia --project=. ParallelRunnerKit/src/setup.jl --sync HOST1 HOST2 ...

# 分散実行
julia --project=. ParallelRunnerKit/src/runner.jl --local N HOST1:W HOST2:W ... scripts/jobs.jl [args...]

# ワーカー数の目安
julia --project=. ParallelRunnerKit/src/suggest_workers.jl --local HOST1 HOST2
```

- パスは `ParallelRunnerKit/src/` 付き (submodule 名が違えば読み替える)。
- ワーカーで load するモジュール名がホストの `name` と違うときは `--package NAME`。

### 2-b. このリポジトリ単体で試す

キット開発・検証用。パスは `src/` 付き (`ParallelRunnerKit/` プレフィックスなし)。

```bash
git clone https://github.com/daihiko-lab/ParallelRunnerKit.jl.git
cd ParallelRunnerKit.jl
julia --project=. -e 'using Pkg; Pkg.instantiate()'

julia --project=. src/runner.jl --local 2 templates/script_template.jl
julia --project=. src/setup.jl --help
```

ヘルプ:

```bash
julia --project=. ParallelRunnerKit/src/runner.jl --help    # 2-a
julia --project=. src/runner.jl --help                      # 2-b
```

## 環境・SSH の基準

リモートホストを使う場合 (1/2 共通)、次を事前に満たしておく。

- 1 (パッケージアプリ): `psetup --check HOST ...`
- 2 (CLI): `julia --project=. ParallelRunnerKit/src/setup.jl --check HOST ...`

### 検証環境

- 開発・検証は macOS のみ (他 OS は未検証)
- Julia 1.12+ をローカルおよび各リモートにインストール
- ローカルに Git、OpenSSH (`ssh`)、rsync があること

### SSH の基準

| 項目 | 基準 |
|------|------|
| 認証 | 鍵認証のみ (パスワード入力なし)。`BatchMode=yes` 相当で非対話接続できること |
| 接続確認 | 各ホストで `ssh HOST echo ok` が成功すること |
| ホスト指定 | `host` または `host:N` (ワーカー数) |
| カスタム SSH オプション | `export DISTRIBUTED_SSH_OPTS="-o Foo=bar ..."` |

既定の SSH オプション (`DISTRIBUTED_SSH_OPTS` 未設定時): `BatchMode=yes`, `ConnectTimeout=10`, `StrictHostKeyChecking=accept-new`, keepalive 各種。

### リモート側に必要なもの

| 項目 | 基準 |
|------|------|
| Julia | リモートにインストール済み。未指定時は自動検出。`--julia PATH` または `JULIA_DISTRIBUTED_EXE` |
| Git | `setup --clone` / `--sync` 利用時、リモートから `origin` へ SSH で clone/pull できること |
| リポジトリ配置 | 全ホストで同じコミット (runner が自動照合) |

### パス・ディレクトリの基準

| 役割 | 変数 / オプション | 説明 |
|------|-------------------|------|
| ローカルのプロジェクトルート | 1: `pwd()` または `DISTRIBUTED_PROJECT_ROOT` / 2: `julia --project=.` のディレクトリ | アプリの `Project.toml` がある場所 |
| リモートのリポジトリルート | `DISTRIBUTED_REMOTE_PROJECT_ROOT` または `setup --remote-path` | SSH 先の絶対パス (推奨)。未設定時: `~/親/リポジトリ名` |
| ドライバの出力先 | `ENV["DISTRIBUTED_OUTPUT_DIR"]` | ドライバが `init_output_dir!` で設定 |
| 実行後に回収するディレクトリ | `DISTRIBUTED_COLLECT_DIRS` | コロン区切り |

```bash
cd ~/GitHub/MyApp.jl
psetup --check host1 host2                                           # 1
# julia --project=. ParallelRunnerKit/src/setup.jl --check host1 host2  # 2
```

### 初回セットアップ (リモートあり)

```bash
# 1 (パッケージアプリ)
psetup --clone HOST ...
psetup --instantiate HOST ...
psetup --check HOST ...
psetup --sync HOST ...

# 2 (CLI スクリプト): psetup を ParallelRunnerKit/src/setup.jl に置き換え
```

ローカルのみ (`--local N` のみ) なら SSH / リモートパスは不要。

## トラブルシューティング

| 問題 | 対処 |
|------|------|
| git ハッシュ不一致 | 1: `psetup --sync` / 2: `setup.jl --sync` |
| `attempt to send to unknown socket` | `DISTRIBUTED_INIT_DELAY_SEC=10` |
| リモートで Julia 未検出 | `--julia PATH` または `JULIA_DISTRIBUTED_EXE` |
| それ以外 | 各コマンドの `--help`、[環境・SSH の基準](#環境ssh-の基準) |

## 開発

### 入手方法

`git clone` / submodule、または `Pkg.add(url=...)` / `Pkg.Apps.add(url=...)`。Julia General Registry への登録は未定 (できればいつかは… くらいの話)。

### 生成AIを用いた開発

現段階は vibe-coding により近い。LLM (Cursor 等) が大部分のコード・ドキュメントを書き、メンテナの理解・レビューは追いついていない部分がある。`0.x` の GitHub 公開リポジトリとしてはその前提で動いている。機能面の正しさは、他プロジェクトや研究での実利用を通じて検証していく。

Julia コミュニティでは [LLM 利用の議論](https://discourse.julialang.org/t/should-general-have-a-guideline-or-rule-preventing-registration-of-vibe-coded-packages/133205) や [General の方針](https://github.com/JuliaRegistries/General/blob/master/README.md) で、レビューなしの vibe-coding と人間が理解した AI-assisted の区別が話されている。本リポジトリもその議論を参考にしている。

## ライセンス

MIT。詳細は [`LICENSE`](LICENSE)。
