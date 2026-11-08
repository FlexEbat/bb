import struct, socket, sys
def csum(b):
    if len(b)%2: b+=b'\0'
    s=sum(struct.unpack('!%dH'%(len(b)//2),b)); s=(s>>16)+(s&0xffff); s+=s>>16
    return ~s&0xffff
MAC_A=bytes.fromhex('020000000001'); MAC_B=bytes.fromhex('020000000002')
pk=[]; ts=[1700000000.0]
def emit(frame):
    ts[0]+=0.01; pk.append((ts[0],frame))
def tcp4(src,dst,sp,dp,seq,ack,flags,payload,fwd=True):
    s,d=socket.inet_aton(src),socket.inet_aton(dst)
    th=struct.pack('!HHIIBBHHH',sp,dp,seq,ack,5<<4,flags,65535,0,0)
    ph=s+d+struct.pack('!BBH',0,6,len(th)+len(payload))
    th=th[:16]+struct.pack('!H',csum(ph+th+payload))+th[18:]
    ip=struct.pack('!BBHHHBBH',0x45,0,20+len(th)+len(payload),1,0,64,6,0)+s+d
    ip=ip[:10]+struct.pack('!H',csum(ip))+ip[12:]
    emit((MAC_B+MAC_A if fwd else MAC_A+MAC_B)+b'\x08\x00'+ip+th+payload)
def udp4(src,dst,sp,dp,payload,fwd=True):
    s,d=socket.inet_aton(src),socket.inet_aton(dst)
    uh=struct.pack('!HHHH',sp,dp,8+len(payload),0)
    ph=s+d+struct.pack('!BBH',0,17,len(uh)+len(payload))
    uh=uh[:6]+struct.pack('!H',csum(ph+uh+payload) or 0xffff)
    ip=struct.pack('!BBHHHBBH',0x45,0,20+len(uh)+len(payload),2,0,64,17,0)+s+d
    ip=ip[:10]+struct.pack('!H',csum(ip))+ip[12:]
    emit((MAC_B+MAC_A if fwd else MAC_A+MAC_B)+b'\x08\x00'+ip+uh+payload)
def tcp6(src,dst,sp,dp,seq,ack,flags,payload,fwd=True):
    s,d=socket.inet_pton(socket.AF_INET6,src),socket.inet_pton(socket.AF_INET6,dst)
    th=struct.pack('!HHIIBBHHH',sp,dp,seq,ack,5<<4,flags,65535,0,0)
    ph=s+d+struct.pack('!IHBB',len(th)+len(payload),0,0,6)
    th=th[:16]+struct.pack('!H',csum(ph+th+payload))+th[18:]
    ip=struct.pack('!IHBB',0x60000000,len(th)+len(payload),6,64)+s+d
    emit((MAC_B+MAC_A if fwd else MAC_A+MAC_B)+b'\x86\xdd'+ip+th+payload)
def flow_tcp(v6,c,s,cp,sp,c2s,s2c):
    f=tcp6 if v6 else tcp4
    cs,ss=1000,5000
    f(c,s,cp,sp,cs,0,0x02,b''); f(s,c,sp,cp,ss,cs+1,0x12,b'',False); cs+=1; ss+=1
    f(c,s,cp,sp,cs,ss,0x10,b'')
    for i in range(max(len(c2s),len(s2c))):
        if i<len(c2s):
            f(c,s,cp,sp,cs,ss,0x18,c2s[i]); cs+=len(c2s[i])
            f(s,c,sp,cp,ss,cs,0x10,b'',False)
        if i<len(s2c):
            f(s,c,sp,cp,ss,cs,0x18,s2c[i],False); ss+=len(s2c[i])
            f(c,s,cp,sp,cs,ss,0x10,b'')
ih=bytes(range(20)); pid=b'-TR2940-abcdefghijkl'
hs=b'\x13BitTorrent protocol'+b'\x00\x00\x00\x00\x00\x10\x00\x05'+ih+pid
# 1. BitTorrent over TCP, IPv4, public addresses (TEST-NET ranges are special -> use real-looking ones)
flow_tcp(False,'203.0.113.10','198.51.100.20',41000,6881,[hs,b'\x00\x00\x00\x01\x02',b'\x00\x00\x00\x05\x04\x00\x00\x00\x01'],[hs,b'\x00\x00\x00\x01\x01',b'\x00\x00\x00\x0d\x07'+b'\x00'*12])
# 2. BitTorrent over TCP, IPv6
flow_tcp(True,'2001:db8::10','2001:db8:1::20',42000,6881,[hs,b'\x00\x00\x00\x01\x02'],[hs,b'\x00\x00\x00\x01\x01'])
# 3. DHT over UDP, IPv4
ping=b'd1:ad2:id20:abcdefghij0123456789e1:q4:ping1:t2:aa1:y1:qe'
resp=b'd1:rd2:id20:mnopqrstuv0123456789e1:t2:aa1:y1:re'
for i in range(4):
    udp4('203.0.113.10','198.51.100.30',51000,6881,ping[:-1]+b'e' if i%2 else ping); udp4('198.51.100.30','203.0.113.10',6881,51000,resp,False)
# 4. plain HTTP for contrast
flow_tcp(False,'203.0.113.10','198.51.100.40',43000,80,[b'GET / HTTP/1.1\r\nHost: example.org\r\nUser-Agent: curl\r\n\r\n'],[b'HTTP/1.1 200 OK\r\nContent-Length: 5\r\n\r\nhello'])
with open(sys.argv[1],'wb') as f:
    f.write(struct.pack('<IHHiIII',0xa1b2c3d4,2,4,0,0,65535,1))
    for t,fr in pk:
        f.write(struct.pack('<IIII',int(t),int((t%1)*1e6),len(fr),len(fr))+fr)
print(len(pk),'packets')
