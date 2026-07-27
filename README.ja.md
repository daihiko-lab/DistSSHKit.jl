# SSHRunner.jl

[![CI](https://github.com/daihiko-lab/SSHRunner.jl/actions/workflows/CI.yml/badge.svg)](https://github.com/daihiko-lab/SSHRunner.jl/actions/workflows/CI.yml)
[![codecov](https://codecov.io/gh/daihiko-lab/SSHRunner.jl/graph/badge.svg)](https://codecov.io/gh/daihiko-lab/SSHRunner.jl)
[![Julia 1.12+](https://img.shields.io/badge/Julia-1.12+-blue.svg)](https://julialang.org/)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)

任意の Julia ドライバスクリプトを、ローカル/SSH リモートのプロセスに分散実行する (Distributed.jl。マルチスレッドではない)。ジョブスケジューラのない、SSH で届く数台〜十数台のホスト向け。clone・同期・実行・結果回収までを一通りカバーする。

English: [README.md](README.md)

**状態:** `0.x` (1.0 未満)。マイナー版の間でもインターフェースが変わる可能性がある。

リモートホストを使う場合は、手順の前に [環境・SSH の基準](#環境ssh-の基準) を読むこと。生成AIの利用については [生成AIを用いた開発](#生成aiを用いた開発) を参照。

## インストールと実行

推奨: 通常の Julia パッケージとして `Pkg.add` で入れ、`julia -m SSHRunner` (Julia 1.12+、Pkg Apps 登録不要) で呼ぶ。アプリルート (`Project.toml` があるディレクトリ) で動かす。

```bash
cd MyProject.jl

# 1回だけ: バージョン固定 (rev はタグ名)
julia --project=. -e 'using Pkg; Pkg.add(url="https://github.com/daihiko-lab/SSHRunner.jl.git", rev="vX.Y.Z")'
```

最新のタグ名は [Releases/Tags 一覧](https://github.com/daihiko-lab/SSHRunner.jl/tags) を参照。

```bash
# リモート準備 (初回)
julia --project=. -m SSHRunner setup --clone HOST1 HOST2 ...
julia --project=. -m SSHRunner setup --instantiate HOST1 HOST2 ...

# コード同期
julia --project=. -m SSHRunner setup --sync HOST1 HOST2 ...

# 分散実行
julia --project=. -m SSHRunner runner \
  --local N HOST1:W HOST2:W ... scripts/jobs.jl [args...]

# ワーカー数の目安
julia --project=. -m SSHRunner suggest-workers --local HOST1 HOST2
```

`runner` / `setup` / `suggest-workers` の後ろがそのまま各コマンドの `ARGS` になる。ワーカーで load するモジュール名がホストの `Project.toml` の `name` と違うときは `--package NAME`。

`Pkg.add(url=..., rev=...)` で `Project.toml` に `[deps]` + `[sources]`、`Manifest.toml` に実際に取得したコミットが記録される。バージョンの正本はこの2ファイル (submodule 不要)。更新したいときは `rev` を変えて `Pkg.add` し直す。

## 共通: ドライバスクリプト

分散実行の対象になる Julia スクリプトは、`Main` に次の 2 関数だけを定義する:

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

`runner()` は先に `using Distributed` してからこのスクリプトを `include` するので、`pmap` 等を使うだけなら自分で `using Distributed` を書かなくてもよい (単体で実行・テストする場合は書いておくと安全)。

## 環境・SSH の基準

リモートホストを使う場合、次を事前に満たしておく。`setup()` (または `src/setup.jl --check HOST ...`) で確認できる。

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
| ローカルのプロジェクトルート | `julia --project=.` のディレクトリ、または `DISTRIBUTED_PROJECT_ROOT` | アプリの `Project.toml` がある場所 |
| リモートのリポジトリルート | `DISTRIBUTED_REMOTE_PROJECT_ROOT` または `setup --remote-path` | SSH 先の絶対パス (推奨)。未設定時: `~/親/リポジトリ名` |
| ドライバの出力先 | `ENV["DISTRIBUTED_OUTPUT_DIR"]` | ドライバが `init_output_dir!` で設定 |
| 実行後に回収するディレクトリ | `DISTRIBUTED_COLLECT_DIRS` | コロン区切り |

```bash
cd ~/GitHub/MyProject.jl
julia --project=. -m SSHRunner setup --check host1 host2
```

### 初回セットアップ (リモートあり)

```bash
julia --project=. -m SSHRunner setup --clone HOST ...
julia --project=. -m SSHRunner setup --instantiate HOST ...
julia --project=. -m SSHRunner setup --check HOST ...
julia --project=. -m SSHRunner setup --sync HOST ...
```

ローカルのみ (`--local N` のみ) なら SSH / リモートパスは不要。

## トラブルシューティング

| 問題 | 対処 |
|------|------|
| git ハッシュ不一致 | `julia -m SSHRunner setup --sync ...` |
| `attempt to send to unknown socket` | `DISTRIBUTED_INIT_DELAY_SEC=10` |
| リモートで Julia 未検出 | `--julia PATH` または `JULIA_DISTRIBUTED_EXE` |
| それ以外 | 各サブコマンドの `--help`、[環境・SSH の基準](#環境ssh-の基準) |

## 開発者向け: キットを submodule で開発

キットのコードそのものを編集しながら動作確認したいとき (通常の利用者は不要):

```bash
cd MyProject.jl
git submodule add https://github.com/daihiko-lab/SSHRunner.jl.git SSHRunner
julia --project=. -e 'using Pkg; Pkg.develop(path="SSHRunner")'
```

呼び出し方は `Pkg.add` の場合と同じ (`julia -m SSHRunner runner ...` など)。submodule 内のファイルを直接編集すればすぐ反映される。バージョンの正本は submodule のコミット。

これと `Pkg.add(url=..., rev=...)` は、どちらもバージョンの正本を明示的に選ぶ設計で、Julia General Registry のような自動追従は想定していない。登録自体は将来できたら嬉しいが、今のところ未定。

## 生成AIを用いた開発

現段階は vibe-coding により近い。LLM (Cursor 等) が大部分のコード・ドキュメントを書き、メンテナの理解・レビューは追いついていない部分がある。`0.x` の GitHub 公開リポジトリとしてはその前提で動いている。機能面の正しさは、他プロジェクトや研究での実利用を通じて検証していく。

Julia コミュニティでは [LLM 利用の議論](https://discourse.julialang.org/t/should-general-have-a-guideline-or-rule-preventing-registration-of-vibe-coded-packages/133205) や [General の方針](https://github.com/JuliaRegistries/General/blob/master/README.md) で、レビューなしの vibe-coding と人間が理解した AI-assisted の区別が話されている。本リポジトリもその議論を参考にしている。

## ライセンス

MIT。詳細は [`LICENSE`](LICENSE)。
