#!/usr/bin/env bash
set -e

BASHRC="$HOME/.bashrc"
FZF_DIR="$HOME/.fzf"
BASHRC_BACKUP="$BASHRC.bak_$(date +%Y%m%d%H%M%S)"

echo "🔍 Vérification de fzf..."

# --- Installation fzf si manquant ---
if ! command -v fzf >/dev/null 2>&1; then
    echo "📦 Installation de fzf..."
    git clone --depth 1 https://github.com/junegunn/fzf.git "$FZF_DIR"
    "$FZF_DIR/install" --all
else
    echo "✅ fzf déjà installé."
fi

# --- Sauvegarde du .bashrc ---
echo "💾 Sauvegarde du fichier bashrc → $BASHRC_BACKUP"
cp "$BASHRC" "$BASHRC_BACKUP"

# --- Vérifie si déjà configuré ---
if grep -q "fzf-smart-complete" "$BASHRC"; then
    echo "⚙️ Configuration fzf déjà détectée dans le .bashrc"
else
    echo "🧩 Injection de la configuration fzf complète dans $BASHRC"

    cat >> "$BASHRC" <<'EOF'

###############################################################
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
        start_dir="$PWD"
        cur="$start_dir"

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

# Normalisation du chemin
if command -v realpath >/dev/null 2>&1; then
  F="$(realpath -m -- "$F" 2>/dev/null)"
else
  while [ "${F#//*}" != "$F" ]; do F="${F//\/\//\/}"; done
  F="${F%/./}"; F="${F%/.}"
fi

title="📂  $item"
len=${#title}

# Générer dynamiquement la barre horizontale
bar=""
for ((i=0; i<len; i++)); do
  bar="${bar}-"
done

# Générer les espaces pour les lignes vides
spaces=""
for ((i=0; i<len; i++)); do
  spaces="${spaces} "
done

echo
echo "                                                      +-${bar}-------+"
echo "                                                      |   ${spaces}     |"
echo "                                                      |   $title    |"
echo "                                                      |   ${spaces}     |"
echo "                                                      +-${bar}-------+"
echo

# Preview
if [ -d "$F" ]; then
  ls -a --color=always -- "$F"
elif [ -f "$F" ]; then
  bat --style=numbers --color=always --line-range :200 -- "$F" 2>/dev/null || head -n 200 -- "$F"
else
  echo "⚠️  Aucun aperçu disponible (élément introuvable)"
fi
'
)
            )

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
}

# --- Complétion intelligente améliorée ---
fzf-smart-complete() {
    local line="${READLINE_LINE}"
    local prefix="${line##* }"

    # Si rien n'est écrit → ouvre ton navigateur complet
    if [[ -z "$prefix" ]]; then
        fzf-complete
        return
    fi

    # Cherche les complétions classiques Bash (fichiers, dossiers…)
    local completions
    completions=$(compgen -f -- "$prefix")
    [ -z "$completions" ] && return 0

    local count
    count=$(echo "$completions" | wc -l)

    if [ "$count" -eq 1 ]; then
        # Une seule correspondance → complète directement
        READLINE_LINE="${line%$prefix}${completions}"
        READLINE_POINT=${#READLINE_LINE}
    else
        # Plusieurs → ouvre FZF pour choisir
        local selected
        selected=$(echo "$completions" | fzf --height 40% --ansi --reverse --border \
            --prompt="Choisir ➜ " \
            --preview "if [ -d {} ]; then ls -a --color=always {}; elif [ -f {} ]; then bat --style=numbers --color=always --line-range :100 {} 2>/dev/null || head -n 100 {}; fi")
        [ -z "$selected" ] && return 0
        READLINE_LINE="${line%$prefix}${selected}"
        READLINE_POINT=${#READLINE_LINE}
    fi
}

# --- Nouveau bind TAB : auto/FZF intelligent ---
bind -x '"\t": fzf-smart-complete'

# --- Add pipx local bin to PATH ---
export PATH="$PATH:$HOME/.local/bin"
###############################################################

EOF
fi

# --- Fin et rechargement interactif ---
echo
echo "✅ Installation et configuration FZF terminées."

read -rp "Souhaitez-vous recharger le shell maintenant ? [O/n] " answer
if [[ ! "$answer" =~ ^[nN]$ ]]; then
    echo "♻️  Rechargement du shell..."
    exec bash
else
    echo "ℹ️  Vous pouvez recharger manuellement plus tard avec : source ~/.bashrc"
fi
