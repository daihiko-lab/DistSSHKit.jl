# DistSSHKit.jl

[![CI](https://github.com/daihiko-lab/DistSSHKit.jl/actions/workflows/CI.yml/badge.svg)](https://github.com/daihiko-lab/DistSSHKit.jl/actions/workflows/CI.yml)
[![JETLS](https://github.com/daihiko-lab/DistSSHKit.jl/actions/workflows/jetls.yml/badge.svg)](https://github.com/daihiko-lab/DistSSHKit.jl/actions/workflows/jetls.yml)
[![codecov](https://codecov.io/gh/daihiko-lab/DistSSHKit.jl/graph/badge.svg?token=XWKRUL2DS1)](https://codecov.io/gh/daihiko-lab/DistSSHKit.jl)
[![Aqua QA](https://juliatesting.github.io/Aqua.jl/dev/assets/badge.svg)](https://github.com/JuliaTesting/Aqua.jl)

[![Julia 1.12+](https://img.shields.io/badge/Julia-1.12+-blue.svg)](https://julialang.org/)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)

任意の Julia スクリプトを、ローカル/SSH リモートのプロセスに分散実行する (Distributed.jl, マルチスレッドではない)。ジョブスケジューラのない、SSH で届く数台程度のホスト向け。clone・同期・実行・結果回収までを一通りカバーする。現状、macOSのみ。

English: [README.md](README.md)

> [!IMPORTANT]
> **開発中:** インターフェースはまだ変わる可能性がある。新規利用は [Releases](https://github.com/daihiko-lab/DistSSHKit.jl/releases) の最新タグを `rev` に指定する。当面は最新タグ自体を最新コミットへ更新していく運用のため、厳密な再現性が必要な場合は `rev` にタグ名ではなくコミットハッシュを指定すること。

リモートホストを使う場合は、手順の前に [リモートホストを使う](#リモートホストを使う) を読むこと。生成AIの利用については [生成AIを用いた開発](#生成aiを用いた開発) を参照。

以下のような用途に向く。

- Slurm や PBS のようなジョブスケジューラなしに、SSH でつながる数台にそのままコードを配りたい
- パラメータスイープ、モンテカルロ、複数条件のバッチ実行など、独立したジョブを台数分だけ並べたい
- 各台で同じ Julia プロジェクト (同じ git コミット) を確実に揃えて実行したい
- 実行後にログや結果ファイルを手動でかき集めるのをやめたい

逆に、大規模 HPC クラスタでの運用や、マルチスレッド並列、動的なスケーリングが必要な用途には向かない。使い方は次節から。

## インストールと実行

推奨: 通常の Julia パッケージとして `Pkg.add` で入れ、`julia -m DistSSHKit` (Julia 1.12+) で呼ぶ。アプリルート (`Project.toml` があるディレクトリ) で動かす。

```bash
cd MyProject.jl

# 1回だけ: バージョン固定 (rev はタグ名)
julia --project=. -e 'using Pkg; Pkg.add(url="https://github.com/daihiko-lab/DistSSHKit.jl.git", rev="vX.Y.Z")'
```

推奨タグ名は [Releases](https://github.com/daihiko-lab/DistSSHKit.jl/releases) を参照。

まずはローカルだけで試すとよい (SSH 不要)。同梱 demo をプロジェクトにコピーしてから実行する:

```bash
julia --project=. -m DistSSHKit demo install
julia --project=. -m DistSSHKit runner --local 2 demos/param_sweep.jl
julia --project=. -m DistSSHKit runner --local 2 demos/coin_flip.jl
```

`demo install` でコピーされる `./demos/*.jl` は、1ファイルで完結したテンプレート。そのままエディタで開いて読み・編集できる。既存ファイルは上書きしない (元に戻したいときは `--force`)。

補足:
- コピーせずパッケージ内のパスだけ確認したいとき: `julia --project=. -m DistSSHKit demo list`
- コピー先を指定したいとき: `julia --project=. -m DistSSHKit demo install --dest DIR`

リモートを使う場合はこの流れ:

```bash
# リモート準備 (初回)
julia --project=. -m DistSSHKit setup --clone HOST1 HOST2 ...
julia --project=. -m DistSSHKit setup --instantiate HOST1 HOST2 ...

# コード同期
julia --project=. -m DistSSHKit setup --sync HOST1 HOST2 ...

# 分散実行
julia --project=. -m DistSSHKit runner \
  --local N HOST1:W HOST2:W ... scripts/jobs.jl [args...]

# ワーカー数の目安
julia --project=. -m DistSSHKit suggest-workers --local HOST1 HOST2
```

`runner` / `demo` / `setup` / `suggest-workers` の後ろがそのまま各コマンドの `ARGS` になる。ワーカーで load するモジュール名がホストの `Project.toml` の `name` と違うときは `--package NAME`。

各サブコマンドの詳しいオプションは `--help` で確認できる:

```bash
julia --project=. -m DistSSHKit runner --help
julia --project=. -m DistSSHKit demo --help
julia --project=. -m DistSSHKit setup --help
julia --project=. -m DistSSHKit suggest-workers --help
```

`Pkg.add(url=..., rev=...)` で `Project.toml` に `[deps]` + `[sources]`、`Manifest.toml` に実際に取得したコミットが記録される。バージョンはこの2ファイルで管理する (submodule 不要)。更新したいときは `rev` を変えて `Pkg.add` し直す。

## 実行するスクリプトの書き方

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

動く最小例: [`demos/`](demos/) (パラメータスイープ、コイン投げ)。自分のプロジェクトにコピーして読み書きしたい場合は `demo install` を使う ([インストールと実行](#インストールと実行) 参照)。

`runner()` は先に `using Distributed` してからこのスクリプトを `include` するので、`pmap` 等を使うだけなら自分で `using Distributed` を書かなくてもよい (単体で実行・テストする場合は書いておくと安全)。

## リモートホストを使う

ローカルのみ (`--local N` のみ) ならこの節は丸ごと不要。複数のリモートホストに分散実行したいときは、次を先に済ませておく。開発・検証は macOS のみ (他 OS は未検証)。各ホストに Julia 1.12+ をインストールし、ローカル側には Git・OpenSSH (`ssh`)・rsync が必要。

DistSSHKit は、ユーザーが普段使う `ssh` コマンドでリモートに接続する。ワーカーの起動や結果の回収も、すべてこの接続経由で行う。**パスワード入力なしで接続できること**が前提なので、鍵認証 (`ssh-copy-id` など) を済ませ、各ホストで次が通るか確認する:

```bash
ssh HOST echo ok
```

runner にホストを渡すときは `host` または `host:N` と書く (`N` はそのホストのワーカー数)。例: `runner host1:10 host2:8 script.jl`

SSH のオプションを変えたいときだけ `DISTRIBUTED_SSH_OPTS` を使う (未設定なら、対話なし接続・10秒タイムアウト・初回のホスト鍵は自動受け入れ、という既定値になる):

```bash
export DISTRIBUTED_SSH_OPTS="-o ProxyJump=bastion ..."
```

リモート側には Julia が必要 (未指定なら自動検出。`--julia PATH` または `JULIA_DISTRIBUTED_EXE` でも指定できる)。`setup --clone` / `--sync` を使うなら、各ホストから `origin` へ SSH で clone/pull できること。実行時は全ホストで同じ git コミットになっているかを runner が自動で確認し、ローカルの作業ツリーに未コミットの変更があれば警告する (両方とも `--skip-hash-check` でスキップ可能)。また `setup --check` は各ホストの Julia バージョンがローカルと一致しているかも確認する (メジャー.マイナーの不一致は失敗扱い。`--ignore-julia-version` を渡すと警告に格下げできる。パッチのみの差異は常に警告のみ)。

パスまわりでよく使う変数:

- **ローカルのプロジェクトルート**: `julia --project=.` を実行するディレクトリ。上書きするなら `DISTRIBUTED_PROJECT_ROOT`
- **リモートのリポジトリルート**: `DISTRIBUTED_REMOTE_PROJECT_ROOT` または `setup --remote-path` (未設定時は `~/親/リポジトリ名`)
- **スクリプトの出力先**: `ENV["DISTRIBUTED_OUTPUT_DIR"]` (`init_output_dir!` で設定)
- **実行後に回収するディレクトリ**: `DISTRIBUTED_COLLECT_DIRS` (コロン区切り)

準備ができているか確認するには:

```bash
cd ~/GitHub/MyProject.jl
julia --project=. -m DistSSHKit setup --check host1 host2
```

初回セットアップはこの順で行う:

```bash
# 1. 各ホストにリポジトリを git clone する
julia --project=. -m DistSSHKit setup --clone HOST ...

# 2. 各ホストで Pkg.instantiate して依存パッケージを揃える
julia --project=. -m DistSSHKit setup --instantiate HOST ...

# 3. clone・依存関係・Julia の有無などをまとめて確認する
julia --project=. -m DistSSHKit setup --check HOST ...

# 4. 手元の git コミットに各ホストを揃える (以降、実行のたびにも使う)
julia --project=. -m DistSSHKit setup --sync HOST ...
```

コミットする前に手早く試したいときは、`setup --rsync HOST ...` で git を経由せず rsync だけでツリーをコピーできる。ただし commit も hash 検証も一切行わないため、`--skip-hash-check` なしでは `runner` の git チェックが警告/失敗する可能性が高い。git コミットでの再現性保証がほしい場合は `--sync` を使うこと。

### 推奨ワークフロー: 試行錯誤 vs 本番実行

- **試行錯誤中** (スクリプトをまだ書き換えている段階): `setup --rsync` + `runner --skip-hash-check` でよい。git の一致は気にせず、フィードバックループの速さを優先する
- **本番実行の前**: コミットしてから `setup --sync HOST ...` を実行し、続けて `setup --check HOST ...` を警告なしで通す。残しておきたい結果を `--skip-hash-check` 付きで実行しない。`setup --check` はメジャー.マイナーの不一致のみ失敗扱いで、パッチのみの差異 (例: 1.12.6 vs 1.12.9) は警告止まりのため、公開・保存する結果を出す前は各ホストを同じパッチに揃えてから (例: `juliaup default 1.12.6`)、警告なしで通ることを確認する
- **結果の記録**: `runner` のログ (`results/runner_*.log`) を出力と一緒に保管する。ログ先頭には実行時のサブコマンド引数と、判明する範囲での Julia 実行環境がすでに記録されている

## トラブルシューティング

- **git ハッシュ不一致**: `julia -m DistSSHKit setup --sync ...`
- **`attempt to send to unknown socket`**: `DISTRIBUTED_INIT_DELAY_SEC=10`
- **リモートで Julia 未検出**: `--julia PATH` または `JULIA_DISTRIBUTED_EXE`
- **それ以外**: 各サブコマンドの `--help`、[リモートホストを使う](#リモートホストを使う)

## 開発者向け

キットのコードそのものを編集しながら動作確認したい場合や、PR を出す前の準備・チェック項目は [CONTRIBUTING.ja.md](CONTRIBUTING.ja.md) にまとめている。

## 生成AIを用いた開発

開発初期段階につき、メンテナの理解・レビューがまだ追いついていない部分がある。機能面の正しさは、他プロジェクトや研究での実利用を通じて検証していく。

Julia コミュニティでは [LLM 利用の議論](https://discourse.julialang.org/t/should-general-have-a-guideline-or-rule-preventing-registration-of-vibe-coded-packages/133205) や [General の方針](https://github.com/JuliaRegistries/General/blob/master/README.md) で、レビューなしの vibe-coding と人間が理解した AI-assisted の区別が話されている。本リポジトリもその議論を参考にしている。

## ライセンス

MIT。詳細は [`LICENSE`](LICENSE)。
