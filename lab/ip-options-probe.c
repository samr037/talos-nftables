// Send one IPv4 TCP SYN with a 24-byte IPv4 header (four NOP option bytes).
// This is a lab probe, not part of the Talos extension image.
#define _GNU_SOURCE
#include <arpa/inet.h>
#include <netinet/ip.h>
#include <netinet/tcp.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/socket.h>
#include <unistd.h>

int main(int argc, char **argv) {
    if (argc != 2) {
        fprintf(stderr, "usage: ip-options-probe <destination IPv4>\n");
        return 2;
    }
    unsigned char packet[sizeof(struct iphdr) + 4 + sizeof(struct tcphdr)] = {0};
    struct iphdr *ip = (struct iphdr *)packet;
    struct tcphdr *tcp = (struct tcphdr *)(packet + sizeof(struct iphdr) + 4);
    ip->version = 4;
    ip->ihl = 6;
    ip->ttl = 64;
    ip->protocol = IPPROTO_TCP;
    ip->tot_len = htons(sizeof(packet));
    if (inet_pton(AF_INET, argv[1], &ip->daddr) != 1) {
        fprintf(stderr, "invalid destination IPv4 address\n");
        return 2;
    }
    ip->saddr = ip->daddr;
    memset(packet + sizeof(struct iphdr), 1, 4);
    tcp->source = htons(33333);
    tcp->dest = htons(50000);
    tcp->doff = 5;
    tcp->syn = 1;

    int fd = socket(AF_INET, SOCK_RAW, IPPROTO_RAW);
    if (fd < 0) {
        perror("socket");
        return 1;
    }
    int one = 1;
    if (setsockopt(fd, IPPROTO_IP, IP_HDRINCL, &one, sizeof(one)) != 0) {
        perror("setsockopt");
        close(fd);
        return 1;
    }
    struct sockaddr_in dest = {.sin_family = AF_INET, .sin_port = htons(50000)};
    dest.sin_addr.s_addr = ip->daddr;
    ssize_t written = sendto(fd, packet, sizeof(packet), 0,
                             (struct sockaddr *)&dest, sizeof(dest));
    if (written < 0) {
        perror("sendto");
        close(fd);
        return 1;
    }
    printf("sent %zd-byte IPv4 TCP packet with IHL=6 to %s\n", written, argv[1]);
    close(fd);
    return 0;
}
