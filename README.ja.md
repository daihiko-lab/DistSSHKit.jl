# SSHRunner.jl

[![CI](https://github.com/daihiko-lab/SSHRunner.jl/actions/workflows/CI.yml/badge.svg)](https://github.com/daihiko-lab/SSHRunner.jl/actions/workflows/CI.yml)
[![JETLS](https://github.com/daihiko-lab/SSHRunner.jl/actions/workflows/jetls.yml/badge.svg)](https://github.com/daihiko-lab/SSHRunner.jl/actions/workflows/jetls.yml)
[![codecov](https://codecov.io/gh/daihiko-lab/SSHRunner.jl/graph/badge.svg)](https://codecov.io/gh/daihiko-lab/SSHRunner.jl)
[![Julia 1.12+](https://img.shields.io/badge/Julia-1.12+-blue.svg)](https://julialang.org/)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)

任意の Julia スクリプトを、ローカル/SSH リモートのプロセスに分散実行する (Distributed.jl。マルチスレッドではない)。ジョブスケジューラのない、SSH で届く数台程度のホスト向け。clone・同期・実行・結果回収までを一通りカバーする。

English: [README.md](README.md)

**状態:** `0.x` (1.0 未満)。マイナー版の間でもインターフェースが変わる可能性がある。

リモートホストを使う場合は、手順の前に [リモートホストを使う](#リモートホストを使う) を読むこと。生成AIの利用については [生成AIを用いた開発](#生成aiを用いた開発) を参照。

以下のような用途に向く。

- Slurm や PBS のようなジョブスケジューラなしに、SSH でつながる数台にそのままコードを配りたい
- パラメータスイープ、モンテカルロ、複数条件のバッチ実行など、独立したジョブを台数分だけ並べたい
- 各台で同じ Julia プロジェクト (同じ git コミット) を確実に揃えて実行したい
- 実行後にログや結果ファイルを手動でかき集めるのをやめたい

逆に、大規模 HPC クラスタでの運用や、マルチスレッド並列、動的なスケーリングが必要な用途には向かない。使い方は次節から。

## インストールと実行

推奨: 通常の Julia パッケージとして `Pkg.add` で入れ、`julia -m SSHRunner` (Julia 1.12+) で呼ぶ。アプリルート (`Project.toml` があるディレクトリ) で動かす。

```bash
cd MyProject.jl

# 1回だけ: バージョン固定 (rev はタグ名)
julia --project=. -e 'using Pkg; Pkg.add(url="https://github.com/daihiko-lab/SSHRunner.jl.git", rev="vX.Y.Z")'
```

最新のタグ名は [Releases/Tags 一覧](https://github.com/daihiko-lab/SSHRunner.jl/tags) を参照。

まずはローカルだけで試すとよい (SSH 不要)。ローカルワーカー2つを立てて [`demos/param_sweep.jl`](demos/param_sweep.jl) を実行するだけ:

```bash
julia --project=. -m SSHRunner runner --local 2 demos/param_sweep.jl
```

リモートを使う場合はこの流れ:

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

各サブコマンドの詳しいオプションは `--help` で確認できる:

```bash
julia --project=. -m SSHRunner runner --help
julia --project=. -m SSHRunner setup --help
julia --project=. -m SSHRunner suggest-workers --help
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

動く最小例: [`demos/`](demos/) (パラメータスイープ、コイン投げ)。

`runner()` は先に `using Distributed` してからこのスクリプトを `include` するので、`pmap` 等を使うだけなら自分で `using Distributed` を書かなくてもよい (単体で実行・テストする場合は書いておくと安全)。

## リモートホストを使う

ローカルのみ (`--local N` のみ) ならこの節は丸ごと不要。複数のリモートホストに分散実行したいときは、次を先に済ませておく。開発・検証は macOS のみ (他 OS は未検証)。各ホストに Julia 1.12+ をインストールし、ローカル側には Git・OpenSSH (`ssh`)・rsync が必要。

SSHRunner は、ユーザーが普段使う `ssh` コマンドでリモートに接続する。ワーカーの起動や結果の回収も、すべてこの接続経由で行う。**パスワード入力なしで接続できること**が前提なので、鍵認証 (`ssh-copy-id` など) を済ませ、各ホストで次が通るか確認する:

```bash
ssh HOST echo ok
```

runner にホストを渡すときは `host` または `host:N` と書く (`N` はそのホストのワーカー数)。例: `runner host1:10 host2:8 script.jl`

SSH のオプションを変えたいときだけ `DISTRIBUTED_SSH_OPTS` を使う (未設定なら、対話なし接続・10秒タイムアウト・初回のホスト鍵は自動受け入れ、という既定値になる):

```bash
export DISTRIBUTED_SSH_OPTS="-o ProxyJump=bastion ..."
```

リモート側には Julia が必要 (未指定なら自動検出。`--julia PATH` または `JULIA_DISTRIBUTED_EXE` でも指定できる)。`setup --clone` / `--sync` を使うなら、各ホストから `origin` へ SSH で clone/pull できること。実行時は全ホストで同じ git コミットになっているかを runner が自動で確認する。

パスまわりでよく使う変数:

- **ローカルのプロジェクトルート**: `julia --project=.` を実行するディレクトリ。上書きするなら `DISTRIBUTED_PROJECT_ROOT`
- **リモートのリポジトリルート**: `DISTRIBUTED_REMOTE_PROJECT_ROOT` または `setup --remote-path` (未設定時は `~/親/リポジトリ名`)
- **スクリプトの出力先**: `ENV["DISTRIBUTED_OUTPUT_DIR"]` (`init_output_dir!` で設定)
- **実行後に回収するディレクトリ**: `DISTRIBUTED_COLLECT_DIRS` (コロン区切り)

準備ができているか確認するには:

```bash
cd ~/GitHub/MyProject.jl
julia --project=. -m SSHRunner setup --check host1 host2
```

初回セットアップはこの順で行う:

```bash
# 1. 各ホストにリポジトリを git clone する
julia --project=. -m SSHRunner setup --clone HOST ...

# 2. 各ホストで Pkg.instantiate して依存パッケージを揃える
julia --project=. -m SSHRunner setup --instantiate HOST ...

# 3. clone・依存関係・Julia の有無などをまとめて確認する
julia --project=. -m SSHRunner setup --check HOST ...

# 4. 手元の git コミットに各ホストを揃える (以降、実行のたびにも使う)
julia --project=. -m SSHRunner setup --sync HOST ...
```

## トラブルシューティング

- **git ハッシュ不一致**: `julia -m SSHRunner setup --sync ...`
- **`attempt to send to unknown socket`**: `DISTRIBUTED_INIT_DELAY_SEC=10`
- **リモートで Julia 未検出**: `--julia PATH` または `JULIA_DISTRIBUTED_EXE`
- **それ以外**: 各サブコマンドの `--help`、[リモートホストを使う](#リモートホストを使う)

## 開発者向け: `Pkg.develop` でキットを編集する

キットのコードそのものを編集しながら動作確認したいとき (通常の利用者は不要)。好きな場所に clone して、そのパスを `Pkg.develop` に渡す:

```bash
git clone https://github.com/daihiko-lab/SSHRunner.jl.git ~/dev/SSHRunner.jl
cd MyProject.jl
julia --project=. -e 'using Pkg; Pkg.develop(path=expanduser("~/dev/SSHRunner.jl"))'
```

呼び出し方は `Pkg.add` の場合と同じ (`julia -m SSHRunner runner ...` など)。この clone 先のファイルを直接編集すればすぐ反映される。

### ローカルでの検証

キットの clone ルートで、だいたい次の順に確認する:

```bash
# 1. テスト (単体、runner スモーク、demo、ログ出力など)
julia --project=. -e 'using Pkg; Pkg.test()'

# 2. 静的解析 — `jetls` が PATH にあること (Pkg.Apps.add 後、.zshrc 等で `export PATH="$HOME/.julia/bin:$PATH"` など)
jetls check demos/*.jl test/*.jl src/**/*.jl

# 3. 手動スモーク (README クイックスタートと同じ)
julia --project=. -m SSHRunner runner --local 2 demos/param_sweep.jl
julia --project=. -m SSHRunner runner --local 2 demos/coin_flip.jl
```

`Pkg.test()` は `test/test_demos.jl` で demo も回す。2–3 は push 前の追加確認。

CI では [`CI.yml`](.github/workflows/CI.yml) と [`jetls.yml`](.github/workflows/jetls.yml) も走らせている。

`Pkg.add(url=..., rev=...)` と `Pkg.develop(path=...)` は、どちらも使うバージョンを自分ではっきり決める設計。Julia General Registry のように `[compat]` で自動的に新しいバージョンへ上がっていく仕組みは想定していない。研究用途では特定のコミットに固定して再現性を保ちたいことが多いため。`0.x` のインターフェースが落ち着いたら、見つけてもらいやすくするために General 登録を検討する余地はある。

## 生成AIを用いた開発

現段階は、メンテナの理解・レビューは追いついていない部分がある。`0.x` の GitHub 公開リポジトリとしてはその前提で動いている。機能面の正しさは、他プロジェクトや研究での実利用を通じて検証していく。

Julia コミュニティでは [LLM 利用の議論](https://discourse.julialang.org/t/should-general-have-a-guideline-or-rule-preventing-registration-of-vibe-coded-packages/133205) や [General の方針](https://github.com/JuliaRegistries/General/blob/master/README.md) で、レビューなしの vibe-coding と人間が理解した AI-assisted の区別が話されている。本リポジトリもその議論を参考にしている。

## ライセンス

MIT。詳細は [`LICENSE`](LICENSE)。
