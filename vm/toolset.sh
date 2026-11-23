# Kali's tools. Kali's own box (amd64) ships its whole toolset (kali-linux-default): nothing is
# installed there. Elsewhere, a Debian VM made Kali by kali.sh (on Arm, where Kali has no box),
# gets a small set that serves every lab, the same for each so it hints at no lab's solution:
# Kali's core and the common web, network and password tools. The player installs more with
# `sudo apt install`.
tools='kali-linux-core nmap curl wget netcat-traditional socat dnsutils whois tcpdump jq git vim
  sqlmap gobuster ffuf dirb nikto whatweb hydra john wordlists smbclient impacket-scripts
  python3-requests'
if ! dpkg-query -W -f='${Status}' kali-linux-headless 2>/dev/null | grep -q 'ok installed'; then
  apt-get update
  # shellcheck disable=SC2086 # $keep and $tools are lists of words
  apt-get install -y $keep $tools
fi
