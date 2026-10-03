# Rebuilds the patched dlords.exe from source.
# Usage (Linux/WSL, needs binutils for i386):  python3 build.py path/to/dlords.exe
# Input must be the WSGF-hex-edited January 2006 dlords.exe. Writes dlords_patched.exe next to this script.
import struct,subprocess,sys,os
os.chdir(os.path.dirname(os.path.abspath(__file__)))
subprocess.check_call(['as','--32','patch.s','-o','patch.o'])
subprocess.check_call(['ld','-m','elf_i386','-Ttext=0x32ab000','-e','0','--oformat','binary','patch.o','-o','patch.bin'])
src=bytearray(open(sys.argv[1],'rb').read())
BASE=0x32ab000; SECRAW=0x295000; SECSIZE=0x2000
code=open('patch.bin','rb').read(); assert len(code)<=SECSIZE
sym={}
for l in subprocess.check_output(['nm','patch.o']).decode().split('\n'):
    if l.strip():
        v,t,n=l.split(); sym[n]=BASE+int(v,16)
d=src+bytes(SECSIZE)
d[SECRAW:SECRAW+len(code)]=code
pe=struct.unpack_from('<I',d,0x3c)[0]
nsec=struct.unpack_from('<H',d,pe+6)[0]; optsz=struct.unpack_from('<H',d,pe+20)[0]
sh=pe+24+optsz+40*nsec
assert all(b==0 for b in d[sh:sh+40])
d[sh:sh+40]=struct.pack('<8sIIIIIIHHI',b'.dlfix\0\0',SECSIZE,BASE-0x400000,SECSIZE,SECRAW,0,0,0,0,0xE0000020)
struct.pack_into('<H',d,pe+6,nsec+1)
struct.pack_into('<I',d,pe+24+56,BASE-0x400000+SECSIZE)   # SizeOfImage
OFF=lambda va: va-0x400000
def expect(at,h): assert d[OFF(at):OFF(at)+len(h)//2]==bytes.fromhex(h),(hex(at),d[OFF(at):OFF(at)+len(h)//2].hex())
def jmp(at,target,total):
    d[OFF(at):OFF(at)+total]=b'\xe9'+struct.pack('<i',target-(at+5))+b'\x90'*(total-5)
def callpatch(at,target):
    d[OFF(at):OFF(at)+6]=b'\xe8'+struct.pack('<i',target-(at+5))+b'\x90'
# windowed device, backbuffer = desktop
expect(0x4136e5,'89442430'); d[OFF(0x4136e6)]=0x7c
expect(0x413872,'89442434'); d[OFF(0x413873)]=0x4c
expect(0x4136ef,'8b4620894424108b462489442414'); jmp(0x4136ef,sym['cd_size_hook'],14)
expect(0x413894,'8b46208b4e248b560c83c418'); jmp(0x413894,sym['reset_size_hook'],12)
expect(0x413732,'8b44243085c0751b'); jmp(0x413732,sym['move_hook'],5)
expect(0x551b3b,'8b0de4096000'); jmp(0x551b3b,sym['dpi_hook'],6)
expect(0x40e482,'8b760453538b06535356ff5044'); jmp(0x40e482,sym['present_hook'],13)
expect(0x5519a7,'8bd38bcbc1ea1081e1ffff0000e8e7c6f4ff'); jmp(0x5519a7,sym['mouse_hook'],18)
expect(0x49e109,'3bf1741d8b46043bc174168b086a018b1544aaa700528b1540aaa7005250ff512c'); jmp(0x49e109,sym['setcur_hook'],0x21)
expect(0x49e181,'a1c03b1f038b0dc43b1f03'); jmp(0x49e181,sym['clip_hook'],11)
expect(0x4478d5,'6a006a008b4004'); jmp(0x4478d5,sym['stretch_hook'],7)
expect(0x413633,'752d'); d[OFF(0x413633)]=0xeb     # render size = game resolution, not window
# viewport + 2D draw wrappers
expect(0x413c2d,'ff90bc000000'); callpatch(0x413c2d,sym['my_setvp'])
for a in (0x40d532,0x40d7f3,0x40db5c,0x40de0f,0x40df25,0x40e1cd,0x40f13f,0x40f281,0x40f3d7,0x40f3fe,0x410a64,0x410dd2,0x411782,0x4117a8,0x411bd8,0x46aa5b,0x46b06e,0x5ae58a):
    b=d[OFF(a):OFF(a)+6]; assert b[0]==0xff and b[1] in (0x90,0x91,0x92) and b[2:]==bytes.fromhex('4c010000'),hex(a)
    callpatch(a,sym['my_dpup'])
for a in (0x46afe7,0x5ae523):
    b=d[OFF(a):OFF(a)+6]; assert b[0]==0xff and b[1] in (0x90,0x91,0x92) and b[2:]==bytes.fromhex('50010000'),hex(a)
    callpatch(a,sym['my_dipup'])
# 1920x1080 slot: tidy floats + avatar layout (from v6)
expect(0x4336bb,'c705e8096000aeffc744'); struct.pack_into('<f',d,OFF(0x4336bb)+6,1919.99)
expect(0x4336c5,'c705ec096000aeff9544'); struct.pack_into('<f',d,OFF(0x4336c5)+6,1079.99)
expect(0x4e2ec2,'d825484e5d00'); struct.pack_into('<I',d,OFF(0x4e2ec2)+2,sym['avatarK'])
for at,v in ((0x4e2ed2,460.0),(0x4e2edc,7777.0),(0x4e2ee6,641.0),(0x4e2ef0,9197.0),(0x4e31a0,-5920.0),(0x4e31aa,767.5),(0x4e31b4,-8950.0)):
    assert d[OFF(at)]==0xc7 and d[OFF(at)+1]==0x05; struct.pack_into('<f',d,OFF(at)+6,v)

# software UI copies -> scaled texture
expect(0x40f620,'a1c83b1f03'); jmp(0x40f620,sym['ui_hook0'],5)
expect(0x40f820,'a1c83b1f03'); jmp(0x40f820,sym['ui_hook1'],5)
expect(0x5518af,'83fe200f87d5000000'); jmp(0x5518af,sym['close_hook'],9)
# mode lookup fallback
expect(0x4135ce,'6848156000'); jmp(0x4135ce,sym['mode_accept'],5)
# 5th resolution slot (was 2048x1536) -> 1280x720
expect(0x4336e9,'c705e00960000008'); struct.pack_into('<I',d,OFF(0x4336e9)+6,1280)
expect(0x4336f3,'c705e40960000006'); struct.pack_into('<I',d,OFF(0x4336f3)+6,720)
struct.pack_into('<f',d,OFF(0x4336fd)+6,1279.99); struct.pack_into('<f',d,OFF(0x433707)+6,719.99)
expect(0x4e2f08,'d825444e5d00'); struct.pack_into('<I',d,OFF(0x4e2f08)+2,sym['avatarK6'])
for at,v in ((0x4e2f18,483.0),(0x4e2f22,2850.0),(0x4e2f2c,-415.0),(0x4e2f36,6016.0),(0x4e31c0,-3463.0),(0x4e31ca,-556.0),(0x4e31d4,-5856.0)):
    assert d[OFF(at)]==0xc7 and d[OFF(at)+1]==0x05,hex(at); struct.pack_into('<f',d,OFF(at)+6,v)
open('dlords_patched.exe','wb').write(d)
print({k:hex(v) for k,v in sym.items() if not k.startswith(('s_','1','2'))})
