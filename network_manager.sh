#!/bin/bash

log_file="net_manager.log"
decor="===================="
full_line="$decor$decor$decor$decor"
choice=""

log () {
    while IFS= read -r line; do
     echo "$line" | tee -a "$log_file"
    done
}

validate_numbers() {
    local str1="$1"
    local str2="$2"

    if ! [[ "$str1" =~ ^[0-9]+$ && "$str2" =~ ^[0-9]+$ ]]; then
        return 1
    fi

    local num1=$str1
    local num2=$str2

    if ((num1 >= 1 && num1 <= num2)); then
        return 0
    else
        return 1
    fi
}

print_title () {
   echo "$full_line" | log
   echo "${decor} $1 - $(date '+%Y-%m-%d %H:%M:%S')" | log
   echo "$full_line" | log
}

print_subtitle () {
   echo "$decor $1" | log
}

check_ip () {
    local ip_cidr="$1"
    local ip_regex="^([0-9]{1,3}\.){3}[0-9]{1,3}\/(3[0-2]|[1-2]?[0-9]|[0-9]|(255\.0\.0\.0|255\.255\.0\.0|255\.255\.255\.0|255\.255\.255\.255))$"

    if [[ "$ip_cidr" =~ $ip_regex ]]; then
        local ip="${ip_cidr%/*}"
        local mask="${ip_cidr#*/}"
        IFS='.' read -ra octets <<< "$ip"

        for octet in "${octets[@]}"; do
            if ((octet < 0 || octet > 255)); then
                return 1
            fi
        done

        return 0
    else
        return 1
    fi
}

network_diagnostic () {
   echo "Which address do you want to test ?"
   read address
   print_title "Network Diagnostic"
   print_subtitle "List Network Interfaces"
   ip -br a | log
   printf "\n$decor Ping Test - Check connectivity $decor\n" | log
   if ! ping -c 3 "$address" | log; then
      echo "Ping failed ($address)" | log
   fi
   printf "\n$decor Traceroute Test - Follow request path $decor\n" | log
   if ! traceroute "$address" | log; then
      echo "Traceroute failed ($address)" | log
   fi
   printf "\n$decor IP Route Test - Display Static Route $decor\n" | log
   if ! ip route | log; then
      echo "IP route failed" | log
   fi
   printf "\n$decor SS Test - List active connexions $decor\n" | log
   if ! ss -tuln | log; then
      echo "SS failed" | log
   fi
}

config_net_interface () {
   echo "interface"
}

change_dns() {
   echo "Do you want to change your DNS for a connection?"
   echo "$decor list of known connections:" | log
   nmcli connection show | grep -v "^NAME\s" | nl | log
   mapfile -t connections < <(nmcli --fields NAME connection show)
   local connection_nb
   read -p "Choose a number:" connection_nb 
   if validate_numbers "$connection_nb" "${#connections[@]}" ; then
      
      connection=$(echo "${connections[connection_nb]}" \
         | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
      echo "Choose a DNS server (Type IP or type DHCP to restore):"
      read dns_server
      if [ "$dns_server" == "DHCP" ] || [ "$dns_server" == "dhcp" ]; then
         nmcli con mod "$connection" ipv4.dns ""
         nmcli con mod "$connection" ipv4.ignore-auto-dns no
         service NetworkManager restart
      else
         echo "Test new DNS with google.com:"
         OLD_IFS="$IFS"
         IFS=','
         read -ra address_array <<< "$dns_server"
         IFS="$OLD_IFS"
         for address in "${address_array[@]}"; do
            nslookup google.com "$address" | log
         done
         echo "Do you want to apply $dns_server ? [Y/n]"
         read apply
         if [ "$apply" == "Y" ] || [ "$apply" == "y" ]; then
            nmcli con mod "$connection" ipv4.dns "$dns_server" | log
            nmcli connection modify "$connection" \
               ipv4.ignore-auto-dns yes | log
            service NetworkManager restart | log
            echo "Dns changes applied" | log
         else
            echo "Error: Not applied" | log
         fi
      fi
   else
      echo "Error: Not valid number." | log
   fi
} 
 
config_dns() {
   print_title "Configure DNS"
   echo "$decor Display binding adresses $decor" | log
   cat /etc/hosts | log
   printf "\n$decor Configure DNS $decor\n" | log
   echo "$decor /etc/hosts file:" | log
   cat /etc/hosts | log
   echo "$decor /etc/nsswitch.conf file:" | log
   cat /etc/nsswitch.conf | grep "hosts:" | log
   echo "$decor /etc/resolv.conf file:"
   cat /etc/resolv.conf | grep -v "^#" | grep -v "^\s*$" | \
      sed 's/$/ (DO NOT MODIFIY - handled by systemd-resolved)/' | log
   if [[ $EUID -ne 0 ]]; then
      echo "Error: Root ou Sudo nedded." | log
   else
      change_dns
   fi
}

capture_traffic () {
   if [[ $EUID -ne 0 ]]; then
      echo "Error: You must be root or launch the program with sudo." | log
      return
   fi
   print_title "Capture Traffic"
   echo "Which connection do you want to capture ?"
   ip -br link show | nl | log
   mapfile -t connections < <(ip -br link show | awk '{print $1}')
   local connection_nb
   read -p "Choose a number:" connection_nb 
   if validate_numbers "$connection_nb" "${#connections[@]}" ; then
      echo "$connection_nb"
      connection=$(echo "${connections[$((connection_nb - 1))]}" \
         | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
      echo "$connection"
      sudo tcpdump -i "$connection" | log
   fi
}

config_fw () {
   if [[ $EUID -ne 0 ]]; then
      echo "Error: You must be root or launch the program with sudo." | log
      return
   fi
   print_title "Config DNS"
   sudo ufw status | log
   echo "What port do you want to manage ?"
   local port
   read port
   echo "Do you want to (delete) allow or (delete) deny ?"
   local action
   read action
   if [ "$action" == "allow" ] || [ "$action" == "deny" ]; then
      sudo ufw "$action" "$port" | log
   elif [[ "$action" == "delete allow" || "$action" == "delete deny" ]]; then
      rule=$(sudo ufw status numbered | grep "$port" | cut -d " " -f1)
      if [[ -n "$rule" ]]; then
           sudo ufw delete "$rule" | log
      else
        echo "Error : No rule for port $port." | log
      fi
   else
      echo "Error: Invalid interface choice." | log
      return
   fi
   sudo ufw status | log
}

config_interface () {
   if [[ $EUID -ne 0 ]]; then
      echo "Error: You must be root or launch the program with sudo."
   fi
   print_title "Config Interface"
   ip -br link show | nl | log
   echo "Which interface you wan't to config ?"
   mapfile -t interfaces < <(ip -br link show | awk '{print $1}')
   local interface
   read -p "Choose a number:" interface_nb 
   if validate_numbers "$interface_nb" "${#interfaces[@]}" ; then
      interface=$(echo "${interfaces[$((interface_nb - 1))]}" \
         | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
      read -p "Enter you new static IP address:" new_ip
      if ! check_ip  "$new_ip"; then
         if ! nmcli con mod "$interface" ipv4.addresses "$new_ip"; then
            echo "Error: Changing IP failed." | log
         else
            echo "New Static IP is validated." | log
         fi
      else
         echo "Error: Invalid IP." | log
      fi
   else
      echo "Error: Invalid interface choice." | log
   fi
}

while [ ! "$choice" == "6" ]; do
   echo "======== NETWORK MANAGER ========"
   echo "1. Network Diagnostic"
   echo "2. Configure Network Interface"
   echo "3. Configure DNS"
   echo "4. Capture Network traffic"
   echo "5. Configure Firewall"
   echo "6. Quit"
   echo "================================="
   echo ""
   echo "Choose an option (1-6) :"
   read choice
   echo ""
   case $choice in
      1) network_diagnostic ;;
      2) config_interface ;;
      3) config_dns ;;
      4) capture_traffic ;;
      5) config_fw ;;
      6) echo "Exiting...";;
      *) echo "Invalid option. Please choose between 1 and 6."; log ;;
    esac
    echo ""
done
