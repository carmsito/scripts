#!/usr/bin/env bash
set -euo pipefail

# === CONFIGURATION ===
BASHRC="$HOME/.bashrc"
BACKUP="$BASHRC.bak_manager_$(date +%Y%m%d%H%M%S)"
FZF_DIR="$HOME/.fzf"

TAG_FZF_START="# === FZF + Bash Enhancements (auto install script) ==="
TAG_FZF_END="###############################################################"
TAG_PROMPT_START="# === Prompt Hacker Pro ==="
TAG_PROMPT_END="# === End Prompt Hacker Pro ==="

echo "🧠  FZF Manager - Gestion interactive de ta configuration Bash"
echo "------------------------------------------------------------"

# === Vérification prérequis ===
if ! command -v git >/dev/null 2>&1; then
  echo "⚠️  Git est requis pour installer fzf. Veuillez l’installer avant de continuer."
  exit 1
fi

# === Sauvegarde du bashrc ===
cp "$BASHRC" "$BACKUP"
echo "💾 Sauvegarde créée → $BACKUP"
echo

# === Fonction d'installation initiale ===
install_initial() {
  echo "🚀 Installation initiale de FZF et de la complétion intelligente..."

  # Installer fzf si absent
  if ! command -v fzf >/dev/null 2>&1; then
      echo "📦 Installation de fzf..."
      git clone --depth 1 https://github.com/junegunn/fzf.git "$FZF_DIR"
      "$FZF_DIR/install" --all
  else
      echo "✅ fzf déjà installé."
  fi

  # Injecter la configuration
  if ! grep -q "fzf-smart-complete" "$BASHRC"; then
      echo "🧩 Injection du bloc FZF..."
      cat >> "$BASHRC" <<'EOF'

# === FZF + Bash Enhancements (auto install script) ===

# --- FZF activation ---
if [ -f ~/.fzf.bash ]; then
    source ~/.fzf.bash
fi

# --- FZF configuration ---
if command -v fd >/dev/null 2>&1; then
    export FZF_DEFAULT_COMMAND='fd --type f --hidden --follow --exclude .git .'
    export FZF_ALT_C_COMMAND='fd --type d --hidden --follow --exclude .git .'
else
    export FZF_DEFAULT_COMMAND='find . -maxdepth 1 -type f'
    export FZF_ALT_C_COMMAND='find . -maxdepth 1 -type d'
fi

export FZF_DEFAULT_OPTS="--height 60% --layout=reverse --border --ansi"

# --- Fuzzy completion function ---
fzf-complete() {
    local line cmd prefix last
    line="${READLINE_LINE}"
    if [ -z "$line" ]; then
        line=$(fc -ln -0 | awk '{$1=""; print substr($0,2)}')
    fi
    cmd=$(printf '%s' "$line" | awk '{print $1}')

    if [[ "$line" =~ [[:space:]]$ ]]; then
        prefix="$line"
        last=""
    else
        last="${line##* }"
        prefix="${line%$last}"
    fi

    if [ -n "$cmd" ] && [ "$prefix" = "" ]; then
        if [ "$line" = "$cmd" ]; then
            prefix="$cmd "
            last=""
        fi
    fi

    _fzf_browser() {
        local start_dir cur sel dirs files
        start_dir="$PWD"; cur="$start_dir"

        while true; do
            dirs=$(find "$cur" -maxdepth 1 -mindepth 1 -type d 2>/dev/null -printf '%P/\n' | sort)
            files=$(find "$cur" -maxdepth 1 -mindepth 1 -type f 2>/dev/null -printf '%P\n' | sort)
            sel=$(
                (printf '%s\n' "./"; printf '%s\n' "../"; printf '%s\n' "$dirs"; printf '%s\n' "$files") |
                (FZF_CUR="${cur}" fzf --ansi --no-hscroll --preview-window=right:60% \
                    --prompt="${cur/#$PWD/~}> " \
                    --preview '
item={}
case "$item" in
 "./")  F="$FZF_CUR" ;;
 "../") F="$(dirname "$FZF_CUR")" ;;
 */)    item="${item%/}"; F="${FZF_CUR%/}/$item" ;;
 *)     F="${FZF_CUR%/}/$item" ;;
esac
if command -v realpath >/dev/null 2>&1; then
  F="$(realpath -m -- "$F" 2>/dev/null)"
fi
title="📂  $item"
len=${#title}
bar=""
for ((i=0; i<len; i++)); do bar="${bar}-"; done
spaces=""
for ((i=0; i<len; i++)); do spaces="${spaces} "; done
echo
echo "                                                      +-${bar}-------+"
echo "                                                      |   ${spaces}     |"
echo "                                                      |   $title    |"
echo "                                                      |   ${spaces}     |"
echo "                                                      +-${bar}-------+"
echo
if [ -d "$F" ]; then ls -a --color=always -- "$F"
elif [ -f "$F" ]; then bat --style=numbers --color=always --line-range :200 -- "$F" 2>/dev/null || head -n 200 -- "$F"
else echo "⚠️  Aucun aperçu disponible (élément introuvable)"
fi')
            [ -z "$sel" ] && return 1
            case "$sel" in
                './') printf '%s\n' "$cur"; return 0 ;;
                '../') cur=$(dirname "$cur") ;;
                */) cur="$cur/${sel%/}" ;;
                *) printf '%s\n' "$cur/$sel"; return 0 ;;
            esac
        done
    }
    local result
    result=$(_fzf_browser) || return 1
    if [ "$cmd" = "cd" ]; then
        if [ -d "$result" ]; then cd -- "$result" || return 1
        else cd -- "$(dirname -- "$result")" || return 1
        fi
        READLINE_LINE=''; READLINE_POINT=0
    else
        result="${result#./}"
        READLINE_LINE="${prefix}${result}"
        READLINE_POINT=${#READLINE_LINE}
    fi
}

# --- Complétion intelligente ---
fzf-smart-complete() {
    local line="${READLINE_LINE}" prefix="${line##* }"
    if [[ -z "$prefix" ]]; then fzf-complete; return; fi
    local completions; completions=$(compgen -f -- "$prefix")
    [ -z "$completions" ] && return 0
    local count; count=$(echo "$completions" | wc -l)
    if [ "$count" -eq 1 ]; then
        READLINE_LINE="${line%$prefix}${completions}"
        READLINE_POINT=${#READLINE_LINE}
    else
        local selected
        selected=$(echo "$completions" | fzf --height 40% --ansi --reverse --border \
            --prompt="Choisir ➜ " \
            --preview "if [ -d {} ]; then ls -a --color=always {}; elif [ -f {} ]; then bat --style=numbers --color=always --line-range :100 {} 2>/dev/null || head -n 100 {}; fi")
        [ -z "$selected" ] && return 0
        READLINE_LINE="${line%$prefix}${selected}"
        READLINE_POINT=${#READLINE_LINE}
    fi
}
bind -x '"\t": fzf-smart-complete'
export PATH="$PATH:$HOME/.local/bin"

###############################################################
EOF
  fi

  echo "✅ Installation FZF terminée."
}

# === Bloc prompt Hacker Pro ===
add_prompt_hackerpro() {
  cat >> "$BASHRC" <<'EOF'

# === Prompt Hacker Pro ===
if [ -f /usr/share/git/completion/git-prompt.sh ]; then
  . /usr/share/git/completion/git-prompt.sh
fi

set_bash_prompt() {
  printf "\033[2K\r"
  local exit_code=$?
  local arrow
  if [ $exit_code -eq 0 ]; then
    arrow="\[\033[38;5;82m\]╰─❯"
  else
    arrow="\[\033[38;5;196m\]╰─✘"
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
EOF
}

# === Menu CLI avec FZF ===
cli_menu() {
  local choice
  choice=$(printf "🔧 Activer FZF\n🚫 Désactiver FZF\n🎨 Activer Prompt Hacker Pro\n🔙 Désactiver Prompt Hacker Pro\n🔁 Recharger le shell\n❌ Quitter" | \
    fzf --height=40% --border --ansi --prompt="Choisir une action ➜ ")

  case "$choice" in
    "🔧 Activer FZF") sed -i "s/^#\s*\($TAG_FZF_START\)/\1/" "$BASHRC"; echo "✅ Bloc FZF activé." ;;
    "🚫 Désactiver FZF") awk -v s="$TAG_FZF_START" -v e="$TAG_FZF_END" '{if(index($0,s)>0){inblk=1} if(inblk){print "#"$0}else{print}}' "$BASHRC" > "$BASHRC.tmp" && mv "$BASHRC.tmp" "$BASHRC"; echo "❌ Bloc FZF désactivé." ;;
    "🎨 Activer Prompt Hacker Pro") add_prompt_hackerpro; echo "✅ Prompt ajouté." ;;
    "🔙 Désactiver Prompt Hacker Pro") awk -v s="$TAG_PROMPT_START" -v e="$TAG_PROMPT_END" 'BEGIN{inblk=0} {if(index($0,s)>0){inblk=1} if(inblk){next} if(index($0,e)>0){inblk=0;next} print}' "$BASHRC" > "$BASHRC.tmp" && mv "$BASHRC.tmp" "$BASHRC"; echo "❌ Prompt supprimé." ;;
    "🔁 Recharger le shell") echo "♻️  Rechargement..."; exec bash ;;
    "❌ Quitter") echo "👋 À bientôt !"; exit 0 ;;
  esac
}

# === Lancement logique ===
if ! grep -q "$TAG_FZF_START" "$BASHRC"; then
  install_initial
else
  echo "⚙️  FZF déjà installé → Ouverture du menu de gestion"
  cli_menu
fi
