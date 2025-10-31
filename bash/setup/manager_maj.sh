#!/usr/bin/env bash
set -euo pipefail

# ===================== Config =====================
BASHRC="$HOME/.bashrc"
BACKUP="$BASHRC.bak_manager_$(date +%Y%m%d%H%M%S)"
FZF_DIR="$HOME/.fzf"

TAG_FZF_START="# === FZF + Bash Enhancements (auto install script) ==="
TAG_FZF_END="###############################################################"
TAG_PS1_START="# === Prompt Hacker Pro ==="
TAG_PS1_END="# === End Prompt Hacker Pro ==="

# ===================== Utils ======================
msg() { printf "%b\n" "$*"; }

save_backup() {
  cp "$BASHRC" "$BACKUP"
  msg "💾  Sauvegarde : $BACKUP"
}

confirm_reload() {
  echo
  read -rp "♻️  Recharger le shell maintenant ? [O/n] " ans || true
  if [[ ! "${ans:-}" =~ ^[nN]$ ]]; then
    exec bash
  else
    echo "ℹ️  Recharge manuelle :  source ~/.bashrc"
  fi
}

validate_or_restore() {
  if ! bash -n "$BASHRC"; then
    msg "❌  Erreur de syntaxe détectée dans ~/.bashrc. Restauration du backup…"
    cp -f "$BACKUP" "$BASHRC"
    msg "🔁  Backup restauré : $BACKUP"
    return 1
  fi
  return 0
}

block_exists() {
  local tag="$1"
  grep -Fq "$tag" "$BASHRC"
}

comment_block() {
  local start="$1" end="$2"
  awk -v s="$start" -v e="$end" '
    BEGIN{inblk=0}
    {
      if (index($0, s)) { inblk=1; print "#" $0; next }
      if (inblk && index($0, e)) { print "#" $0; inblk=0; next }
      if (inblk) { print "#" $0; next }
      print
    }
  ' "$BASHRC" > "$BASHRC.tmp" && mv "$BASHRC.tmp" "$BASHRC"
}

uncomment_block() {
  local start="$1" end="$2"
  awk -v s="$start" -v e="$end" '
    BEGIN{inblk=0}
    {
      if (index($0, s)) { inblk=1; sub(/^# */,""); print; next }
      if (inblk && index($0, e)) { sub(/^# */,""); print; inblk=0; next }
      if (inblk) { sub(/^# */,""); print; next }
      print
    }
  ' "$BASHRC" > "$BASHRC.tmp" && mv "$BASHRC.tmp" "$BASHRC"
}

is_block_commented() {
  # retourne 0 si TOUTES les lignes du bloc (entre balises) commencent par '#'
  local start="$1" end="$2"
  awk -v s="$start" -v e="$end" '
    BEGIN{inblk=0; commented=1}
    {
      if (index($0, s)) { inblk=1; next }
      if (inblk && index($0, e)) { inblk=0; next }
      if (inblk) {
        if ($0 !~ /^#/) { commented=0 }
      }
    }
    END{ if (commented==1) exit 0; else exit 1 }
  ' "$BASHRC"
}

restore_last_backup() {
  local last
  last=$(ls -1t "$HOME"/.bashrc.bak_manager_* 2>/dev/null | head -n1 || true)
  if [ -z "${last:-}" ]; then
    msg "⚠️  Aucun backup trouvé."
    return 1
  fi
  cp -f "$last" "$BASHRC"
  msg "🔙  Restauré depuis : $last"
  return 0
}

# ===================== Install/inject ======================
ensure_git_and_fzf() {
  if ! command -v git >/dev/null 2>&1; then
    msg "⚠️  Git est requis. Installe-le d’abord."
    exit 1
  fi
  if ! command -v fzf >/dev/null 2>&1; then
    msg "📦  Installation de fzf…"
    git clone --depth 1 https://github.com/junegunn/fzf.git "$FZF_DIR"
    "$FZF_DIR/install" --all
    msg "✅  fzf installé."
  fi
}

inject_fzf_block_once() {
  if block_exists "$TAG_FZF_START"; then
    msg "⚙️  Bloc FZF déjà présent ; pas de réinjection."
    return 0
  fi
  msg "🧩  Ajout du bloc FZF dans .bashrc…"
  {
    printf "\n\n"
    cat <<'__FZF_BLOCK__'
# === FZF + Bash Enhancements (auto install script) ===
if [ -f ~/.fzf.bash ]; then
  source ~/.fzf.bash
fi

# FZF default commands (fd si dispo, sinon find)
if command -v fd >/dev/null 2>&1; then
  export FZF_DEFAULT_COMMAND='fd --type f --hidden --follow --exclude .git .'
  export FZF_ALT_C_COMMAND='fd --type d --hidden --follow --exclude .git .'
else
  export FZF_DEFAULT_COMMAND='find . -maxdepth 1 -type f'
  export FZF_ALT_C_COMMAND='find . -maxdepth 1 -type d'
fi

export FZF_DEFAULT_OPTS="--height 60% --layout=reverse --border --ansi"

fzf-complete() {
  local line cmd prefix last
  line="${READLINE_LINE}"
  if [ -z "$line" ]; then
    line=$(fc -ln -0 | awk '{$1=""; print substr($0,2)}')
  fi
  cmd=$(printf '%s' "$line" | awk '{print $1}')
  if [[ "$line" =~ [[:space:]]$ ]]; then
    prefix="$line"; last=""
  else
    last="${line##* }"; prefix="${line%$last}"
  fi

  _fzf_browser() {
    local start_dir cur sel dirs files
    start_dir="$PWD"; cur="$start_dir"

    while true; do
      dirs=$(find "$cur" -maxdepth 1 -mindepth 1 -type d -printf '%P/\n' 2>/dev/null | sort)
      files=$(find "$cur" -maxdepth 1 -mindepth 1 -type f -printf '%P\n' 2>/dev/null | sort)

      sel=$(
        (printf '%s\n' "./"; printf '%s\n' "../"; printf '%s\n' "$dirs"; printf '%s\n' "$files") |
        (FZF_CUR="$cur" fzf --ansi --no-hscroll --preview-window=right:60% \
          --prompt="${cur/#$PWD/~}> " \
          --preview "ITEM={}; F=\$FZF_CUR;
            case \"\$ITEM\" in
              \"./\")  F=\"\$FZF_CUR\" ;;
              \"../\") F=\$(dirname \"\$FZF_CUR\") ;;
              */)     ITEM=\${ITEM%/}; F=\"\${FZF_CUR%/}/\$ITEM\" ;;
              *)      F=\"\${FZF_CUR%/}/\$ITEM\" ;;
            esac
            if [ -d \"\$F\" ]; then
              ls -a --color=always -- \"\$F\"
            elif [ -f \"\$F\" ]; then
              bat --style=numbers --color=always --line-range :200 -- \"\$F\" 2>/dev/null || head -n 200 -- \"\$F\"
            else
              echo \"No preview\" 1>&2
            fi"
        )
      )

      [ -z "$sel" ] && return 1

      case "$sel" in
        './') printf '%s\n' "$cur"; return 0 ;;
        '../') cur=$(dirname "$cur") ;;
        */)   cur="$cur/${sel%/}" ;;
        *)    printf '%s\n' "$cur/$sel"; return 0 ;;
      esac
    done
  }  # fin _fzf_browser

  local result
  result=$(_fzf_browser) || return 1
  if [ "$cmd" = "cd" ]; then
    if [ -d "$result" ]; then
      cd -- "$result" || return 1
    else
      cd -- "$(dirname -- "$result")" || return 1
    fi
    READLINE_LINE=''
    READLINE_POINT=0
  else
    result="${result#./}"
    READLINE_LINE="${prefix}${result}"
    READLINE_POINT=${#READLINE_LINE}
  fi
}  # fin fzf-complete

# Complétion intelligente
fzf-smart-complete() {
  local line="${READLINE_LINE}" prefix="${line##* }"

  if [[ -z "$prefix" ]]; then
    fzf-complete
    return
  fi

  local completions
  completions=$(compgen -f -- "$prefix") || return 0
  [ -z "$completions" ] && return 0

  local count
  count=$(echo "$completions" | wc -l)

  if [ "$count" -eq 1 ]; then
    READLINE_LINE="${line%$prefix}${completions}"
    READLINE_POINT=${#READLINE_LINE}
  else
    local selected
    selected=$(echo "$completions" | fzf --height 40% --ansi --reverse --border \
      --prompt="Choisir ➜ " \
      --preview "if [ -d {} ]; then ls -a --color=always {}; elif [ -f {} ]; then bat --style=numbers --color=always --line-range :100 {} 2>/dev/null || head -n 100 {}; else echo 'No preview' 1>&2; fi")
    [ -z "$selected" ] && return 0
    READLINE_LINE="${line%$prefix}${selected}"
    READLINE_POINT=${#READLINE_LINE}
  fi
}  # fin fzf-smart-complete

# Binding TAB
bind -x '"\t": fzf-smart-complete'

# PATH local
export PATH="$PATH:$HOME/.local/bin"
###############################################################
__FZF_BLOCK__
    printf "\n"
  } >> "$BASHRC"

  validate_or_restore || return 1
  msg "✅  Bloc FZF injecté."
  return 0
}

inject_ps1_block_once() {
  if block_exists "$TAG_PS1_START"; then
    msg "⚙️  Bloc PS1 déjà présent ; pas de réinjection."
    return 0
  fi
  msg "🎨  Ajout du bloc PS1 Hacker Pro dans .bashrc…"
  {
    printf "\n\n"
    cat <<'__PS1_BLOCK__'
# === Prompt Hacker Pro ===
if [ -f /usr/share/git/completion/git-prompt.sh ]; then
  . /usr/share/git/completion/git-prompt.sh
fi

set_bash_prompt() {
  # Efface la ligne précédente du prompt (évite les résidus)
  printf "\033[2K\r"

  local exit_code=$?
  local arrow
  if [ $exit_code -eq 0 ]; then
      arrow="\[\033[38;5;82m\]╰─❯"    # Vert
  else
      arrow="\[\033[38;5;196m\]╰─✘"   # Rouge
  fi

  PS1="\n\[\033[38;5;82m\]╭─["\
"\[\033[38;5;45m\]\u@\h"\
"\[\033[38;5;82m\]]-["\
"\[\033[38;5;226m\]\d \t"\
"\[\033[38;5;82m\]]-["\
"\[\033[38;5;10m\]\$(echo \"\$PWD\" | sed \"s|^$HOME|~|\")"\
"\[\033[38;5;245m\]\$(__git_ps1 ' (%s)')"\
"\[\033[38;5;82m\]]\n${arrow} "\
"\[\033[00m\]"
}
PROMPT_COMMAND=set_bash_prompt
# === End Prompt Hacker Pro ===
__PS1_BLOCK__
    printf "\n"
  } >> "$BASHRC"

  validate_or_restore || return 1
  msg "✅  Bloc PS1 injecté."
  return 0
}

# ===================== Menu ======================
menu() {
  local choice
  if command -v fzf >/dev/null 2>&1; then
    choice=$(printf "🔧 Activer FZF\n🚫 Désactiver FZF\n🎨 Activer PS1 Hacker Pro\n🔙 Désactiver PS1 Hacker Pro\n🕘 Restaurer dernière backup\n❌ Quitter" \
      | fzf --prompt="Choisis une action ➜ " --height 40% --border --ansi)
  else
    echo "1) Activer FZF"
    echo "2) Désactiver FZF"
    echo "3) Activer PS1 Hacker Pro"
    echo "4) Désactiver PS1 Hacker Pro"
    echo "5) Restaurer dernière backup"
    echo "6) Quitter"
    read -rp "Choix: " num
    case "${num:-}" in
      1) choice="🔧 Activer FZF" ;;
      2) choice="🚫 Désactiver FZF" ;;
      3) choice="🎨 Activer PS1 Hacker Pro" ;;
      4) choice="🔙 Désactiver PS1 Hacker Pro" ;;
      5) choice="🕘 Restaurer dernière backup" ;;
      *) choice="❌ Quitter" ;;
    esac
  fi

  case "${choice:-}" in
    "🔧 Activer FZF")
      save_backup
      if ! block_exists "$TAG_FZF_START"; then
        ensure_git_and_fzf
        inject_fzf_block_once || exit 1
      else
        uncomment_block "$TAG_FZF_START" "$TAG_FZF_END"
        validate_or_restore || exit 1
        msg "✅  FZF activé."
      fi
      confirm_reload
      ;;
    "🚫 Désactiver FZF")
      if ! block_exists "$TAG_FZF_START"; then
        msg "⚠️  Bloc FZF absent."
      else
        save_backup
        comment_block "$TAG_FZF_START" "$TAG_FZF_END"
        validate_or_restore || exit 1
        msg "❌  FZF désactivé."
      fi
      confirm_reload
      ;;
    "🎨 Activer PS1 Hacker Pro")
      save_backup
      if ! block_exists "$TAG_PS1_START"; then
        inject_ps1_block_once || exit 1
      else
        uncomment_block "$TAG_PS1_START" "$TAG_PS1_END"
        validate_or_restore || exit 1
        msg "✅  PS1 activé."
      fi
      confirm_reload
      ;;
    "🔙 Désactiver PS1 Hacker Pro")
      if ! block_exists "$TAG_PS1_START"; then
        msg "⚠️  Bloc PS1 absent."
      else
        save_backup
        comment_block "$TAG_PS1_START" "$TAG_PS1_END"
        validate_or_restore || exit 1
        msg "❌  PS1 désactivé."
      fi
      confirm_reload
      ;;
    "🕘 Restaurer dernière backup")
      if restore_last_backup; then
        validate_or_restore || exit 1
        confirm_reload
      else
        : # rien
      fi
      ;;
    *)
      msg "👋  Fin."
      exit 0
      ;;
  esac
}

# ===================== Main ======================
msg "🧠  FZF Manager — Gestion interactive Bash"
msg "-------------------------------------------"
save_backup
ensure_git_and_fzf

# 1ère exécution : injecter FZF si absent (puis menu)
if ! block_exists "$TAG_FZF_START"; then
  inject_fzf_block_once || exit 1
fi

# Ouvrir le menu à chaque lancement
menu
