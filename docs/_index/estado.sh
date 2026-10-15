#!/usr/bin/env sh
# Derived state of EnochDB epics and sprints. Read-only: it edits nothing.
# Usage: sh docs/_index/estado.sh
set -eu

here=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
docs=$(CDPATH= cd -- "$here/.." && pwd)

campo() { # campo <file> <key>
  awk -v k="$2" '
    index($0, k ":") == 1 {
      v = $0
      sub("^" k ":[ \t]*", "", v)
      sub(/[ \t]+#.*$/, "", v)
      sub(/[ \t]+$/, "", v)
      print v
      exit
    }' "$1"
}

estado_sprint() { # estado_sprint <sprint-dir>
  d="$1"; total=0; vazio=0; fim=0
  for f in "$d"/*/CONTEXT.md; do
    [ -e "$f" ] || continue
    total=$((total + 1))
    case "$(campo "$f" status)" in
      vazio) vazio=$((vazio + 1)) ;;
      fechado | nao-aplicavel) fim=$((fim + 1)) ;;
    esac
  done
  if [ "$total" -eq 0 ] || [ "$vazio" -eq "$total" ]; then
    echo vazio
  elif [ "$fim" -eq "$total" ]; then
    echo fechado
  else
    echo em-curso
  fi
}

echo "# Epics"
for f in "$docs"/epicos/*.md; do
  [ -e "$f" ] || continue
  base=$(basename "$f" .md)
  [ "$base" = "README" ] && continue
  printf -- '- %-16s [%s]  %s\n' "$base" "$(campo "$f" status)" "$(campo "$f" titulo)"
done

echo
echo "# Sprints"
for d in "$docs"/_sprints/*/; do
  [ -d "$d" ] || continue
  base=$(basename "$d")
  ficha="$d/CONTEXT.md"
  epico=—
  [ -e "$ficha" ] && epico=$(campo "$ficha" epico)
  printf -- '- %-16s [%s]  epico=%s\n' "$base" "$(estado_sprint "$d")" "$epico"
done

echo
echo "# Backlog (without sprint)"
for f in "$docs"/_backlog/B*.md; do
  [ -e "$f" ] || continue
  printf -- '- %-34s epico_sugerido=%s  %s\n' "$(basename "$f" .md)" "$(campo "$f" epico_sugerido)" "$(campo "$f" titulo)"
done
