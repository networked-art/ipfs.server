#!/bin/sh

set -eu

external_interface="${DOCKER_EGRESS_INTERFACE:-enp41s0}"
chain="DOCKER-USER"
comment="evm-now-rainbow-special-use-egress"

iptables -nL "$chain" >/dev/null
ip6tables -nL "$chain" >/dev/null

# Reject new container connections to non-public IPv4 destinations. The rule
# is tied to the physical interface so Docker's internal bridge remains usable.
for network in \
  0.0.0.0/8 \
  10.0.0.0/8 \
  100.64.0.0/10 \
  127.0.0.0/8 \
  169.254.0.0/16 \
  172.16.0.0/12 \
  192.0.0.0/24 \
  192.0.2.0/24 \
  192.168.0.0/16 \
  198.18.0.0/15 \
  198.51.100.0/24 \
  203.0.113.0/24 \
  224.0.0.0/4 \
  240.0.0.0/4
do
  iptables -C "$chain" -o "$external_interface" -d "$network" \
    -m conntrack --ctstate NEW -m comment --comment "$comment" \
    -j REJECT --reject-with icmp-admin-prohibited 2>/dev/null || \
    iptables -I "$chain" 1 -o "$external_interface" -d "$network" \
      -m conntrack --ctstate NEW -m comment --comment "$comment" \
      -j REJECT --reject-with icmp-admin-prohibited
done

# Cover host-originated traffic too. This protects any future non-Docker
# retrieval helper and makes the policy independent of the execution model.
for network in \
  0.0.0.0/8 \
  10.0.0.0/8 \
  100.64.0.0/10 \
  127.0.0.0/8 \
  169.254.0.0/16 \
  172.16.0.0/12 \
  192.0.0.0/24 \
  192.0.2.0/24 \
  192.168.0.0/16 \
  198.18.0.0/15 \
  198.51.100.0/24 \
  203.0.113.0/24 \
  224.0.0.0/4 \
  240.0.0.0/4
do
  iptables -C OUTPUT -o "$external_interface" -d "$network" \
    -m conntrack --ctstate NEW -m comment --comment "$comment" \
    -j REJECT --reject-with icmp-admin-prohibited 2>/dev/null || \
    iptables -I OUTPUT 1 -o "$external_interface" -d "$network" \
      -m conntrack --ctstate NEW -m comment --comment "$comment" \
      -j REJECT --reject-with icmp-admin-prohibited
done

for network in \
  ::/3 \
  ::1/128 \
  100::/64 \
  2001:2::/48 \
  2001:db8::/32 \
  fc00::/7 \
  fe80::/10
do
  ip6tables -C "$chain" -o "$external_interface" -d "$network" \
    -m conntrack --ctstate NEW -m comment --comment "$comment" \
    -j REJECT --reject-with icmp6-adm-prohibited 2>/dev/null || \
    ip6tables -I "$chain" 1 -o "$external_interface" -d "$network" \
      -m conntrack --ctstate NEW -m comment --comment "$comment" \
      -j REJECT --reject-with icmp6-adm-prohibited
done
