.intel_syntax noprefix
.code32
# ===================== data =====================
deskW:       .long 0
deskH:       .long 0
fromOS:      .long 0
rect_left:   .long 0
rect_top:    .long 0
rect_right:  .long 0
rect_bottom: .long 0
avatarK:     .float 4105.0
avatarK6:    .float 1727.0
half:        .float 0.5
sx:          .float 0
sy:          .float 0
fleft:       .float 0
ftop:        .float 0
tmpbuf:      .long 0
vp_valid:    .long 0
vp_scaled:   .long 0,0,0,0,0,0
vp_full:     .long 0,0,0,0,0,0x3f800000
ui_tex:      .long 0
ui_texW:     .long 0
ui_texH:     .long 0
ui_sb:       .long 0
ui_lr_c:     .long 0,0
ui_lr_t:     .long 0,0
ui_rect:     .long 0,0,0,0
ui_verts:    .long 0,0,0,0,0,0, 0,0,0,0,0,0, 0,0,0,0,0,0, 0,0,0,0,0,0
bar_rects:   .long 0,0,0,0, 0,0,0,0
s_user32:    .asciz "user32.dll"
s_dpi:       .asciz "SetProcessDPIAware"
.balign 4
TMPSIZE = 0x100000

# ===================== helpers =====================
# device pointer -> eax (0 if none)
get_dev:
  mov eax, dword ptr ds:0x31f3bc8
  test eax, eax
  jz 1f
  mov eax, dword ptr [eax+4]
1:ret

# rect of the game image (game resolution) inside the desktop-sized backbuffer
# returns eax=&rect or 0 ; clobbers ecx, edx
calc_rect:
  cmp dword ptr [deskW], 0
  je calc_none
  cmp dword ptr ds:0x6009e0, 0
  je calc_none
  cmp dword ptr ds:0x6009e4, 0
  je calc_none
  push edi
  mov eax, dword ptr ds:0x6009e0
  imul eax, dword ptr [deskH]
  mov edx, dword ptr ds:0x6009e4
  imul edx, dword ptr [deskW]
  cmp eax, edx
  jl calc_pillar
  mov eax, dword ptr [deskW]
  imul eax, dword ptr ds:0x6009e4
  cdq
  idiv dword ptr ds:0x6009e0
  mov edi, eax
  mov eax, dword ptr [deskH]
  sub eax, edi
  sar eax, 1
  mov dword ptr [rect_top], eax
  add eax, edi
  mov dword ptr [rect_bottom], eax
  mov dword ptr [rect_left], 0
  mov eax, dword ptr [deskW]
  mov dword ptr [rect_right], eax
  jmp calc_done
calc_pillar:
  mov eax, dword ptr [deskH]
  imul eax, dword ptr ds:0x6009e0
  cdq
  idiv dword ptr ds:0x6009e4
  mov edi, eax
  mov eax, dword ptr [deskW]
  sub eax, edi
  sar eax, 1
  mov dword ptr [rect_left], eax
  add eax, edi
  mov dword ptr [rect_right], eax
  mov dword ptr [rect_top], 0
  mov eax, dword ptr [deskH]
  mov dword ptr [rect_bottom], eax
calc_done:
  pop edi
  mov eax, offset rect_left
  ret
calc_none:
  xor eax, eax
  ret

# eax = 1 if the game image maps 1:1 onto the backbuffer
is_identity:
  call calc_rect
  test eax, eax
  jz ident_yes
  cmp dword ptr [rect_left], 0
  jne ident_no
  cmp dword ptr [rect_top], 0
  jne ident_no
  mov eax, dword ptr [rect_right]
  cmp eax, dword ptr ds:0x6009e0
  jne ident_no
  mov eax, dword ptr [rect_bottom]
  cmp eax, dword ptr ds:0x6009e4
  jne ident_no
ident_yes:
  mov eax, 1
  ret
ident_no:
  xor eax, eax
  ret

# make sure deskW/H are known. edx = IDirect3D9*, ecx = adapter. preserves all but eax
ensure_desk:
  cmp dword ptr [deskW], 0
  jne ed_ret
  push ecx
  push edx
  sub esp, 16
  mov eax, esp
  push eax
  push ecx
  push edx
  mov eax, dword ptr [edx]
  call dword ptr [eax+0x20]          # GetAdapterDisplayMode
  test eax, eax
  jne ed_fail
  mov eax, dword ptr [esp]
  mov dword ptr [deskW], eax
  mov eax, dword ptr [esp+4]
  mov dword ptr [deskH], eax
ed_fail:
  add esp, 16
  pop edx
  pop ecx
ed_ret:
  ret

# copy nv vertices (esi=src, ecx=nv, edx=stride) into tmpbuf and scale x,y
# returns eax = tmpbuf or 0
scale_verts:
  push ebx
  push edi
  push esi
  mov eax, ecx
  imul eax, edx
  cmp eax, TMPSIZE
  ja sv_fail
  test eax, eax
  jz sv_fail
  cmp dword ptr [tmpbuf], 0
  jne sv_have
  push ecx
  push edx
  push eax
  push 1
  push TMPSIZE
  call 0x5afe3d                      # calloc
  add esp, 8
  mov dword ptr [tmpbuf], eax
  pop eax
  pop edx
  pop ecx
  cmp dword ptr [tmpbuf], 0
  je sv_fail
sv_have:
  mov ebx, ecx                        # nv
  mov edi, dword ptr [tmpbuf]
  push ecx
  mov ecx, eax
  rep movsb
  pop ecx
  # scale factors
  mov eax, dword ptr [rect_right]
  sub eax, dword ptr [rect_left]
  push eax
  fild dword ptr [esp]
  fidiv dword ptr ds:0x6009e0
  fstp dword ptr [sx]
  mov eax, dword ptr [rect_bottom]
  sub eax, dword ptr [rect_top]
  mov dword ptr [esp], eax
  fild dword ptr [esp]
  fidiv dword ptr ds:0x6009e4
  fstp dword ptr [sy]
  fild dword ptr [rect_left]
  fstp dword ptr [fleft]
  fild dword ptr [rect_top]
  fstp dword ptr [ftop]
  pop eax
  mov edi, dword ptr [tmpbuf]
sv_loop:
  fld dword ptr [edi]
  fadd dword ptr [half]
  fmul dword ptr [sx]
  fsub dword ptr [half]
  fadd dword ptr [fleft]
  fstp dword ptr [edi]
  fld dword ptr [edi+4]
  fadd dword ptr [half]
  fmul dword ptr [sy]
  fsub dword ptr [half]
  fadd dword ptr [ftop]
  fstp dword ptr [edi+4]
  add edi, edx
  dec ebx
  jnz sv_loop
  mov eax, dword ptr [tmpbuf]
  jmp sv_out
sv_fail:
  xor eax, eax
sv_out:
  pop esi
  pop edi
  pop ebx
  ret

# is the current FVF pre-transformed (XYZRHW)?  arg: device in ecx. eax=1 yes
fvf_is_rhw:
  push 0
  mov eax, esp
  push eax
  push ecx
  mov eax, dword ptr [ecx]
  call dword ptr [eax+0x168]          # GetFVF
  pop eax
  and eax, 0x0e
  cmp eax, 4
  sete al
  movzx eax, al
  ret

# ===================== DrawPrimitiveUP wrapper =====================
# stdcall (this, type, count, pData, stride)
my_dpup:
  push ebp
  mov ebp, esp
  push ebx
  push esi
  push edi
  sub esp, 8                          # [ebp-16] saved magfilter
  mov ecx, dword ptr [ebp+8]
  call fvf_is_rhw
  test eax, eax
  jz dp_pass
  call is_identity
  test eax, eax
  jnz dp_pass
  mov eax, dword ptr [ebp+16]         # prim count
  mov ecx, dword ptr [ebp+12]         # prim type
  cmp ecx, 4
  je dp_tri
  cmp ecx, 5
  je dp_strip
  cmp ecx, 6
  je dp_strip
  cmp ecx, 2
  je dp_line
  cmp ecx, 3
  je dp_lstrip
  cmp ecx, 1
  je dp_nv
  jmp dp_pass
dp_tri:
  lea eax, [eax+eax*2]
  jmp dp_nv
dp_strip:
  add eax, 2
  jmp dp_nv
dp_line:
  add eax, eax
  jmp dp_nv
dp_lstrip:
  inc eax
dp_nv:
  mov ecx, eax
  mov esi, dword ptr [ebp+20]
  mov edx, dword ptr [ebp+24]
  call scale_verts
  test eax, eax
  jz dp_pass
  mov ebx, eax
  call filt_on
  push dword ptr [ebp+24]
  push ebx
  push dword ptr [ebp+16]
  push dword ptr [ebp+12]
  push dword ptr [ebp+8]
  mov ecx, dword ptr [ebp+8]
  mov ecx, dword ptr [ecx]
  call dword ptr [ecx+0x14c]
  mov ebx, eax
  call filt_off
  mov eax, ebx
  jmp dp_out
dp_pass:
  push dword ptr [ebp+24]
  push dword ptr [ebp+20]
  push dword ptr [ebp+16]
  push dword ptr [ebp+12]
  push dword ptr [ebp+8]
  mov ecx, dword ptr [ebp+8]
  mov ecx, dword ptr [ecx]
  call dword ptr [ecx+0x14c]
dp_out:
  lea esp, [ebp-12]
  pop edi
  pop esi
  pop ebx
  pop ebp
  ret 0x14

# ===================== DrawIndexedPrimitiveUP wrapper =====================
# stdcall (this, type, minIdx, numVerts, primCount, pIdx, idxFmt, pVerts, stride)
my_dipup:
  push ebp
  mov ebp, esp
  push ebx
  push esi
  push edi
  sub esp, 8
  mov ecx, dword ptr [ebp+8]
  call fvf_is_rhw
  test eax, eax
  jz di_pass
  call is_identity
  test eax, eax
  jnz di_pass
  mov ecx, dword ptr [ebp+16]
  add ecx, dword ptr [ebp+20]
  mov esi, dword ptr [ebp+36]
  mov edx, dword ptr [ebp+40]
  call scale_verts
  test eax, eax
  jz di_pass
  mov ebx, eax
  call filt_on
  push dword ptr [ebp+40]
  push ebx
  jmp di_call
di_pass:
  push dword ptr [ebp+40]
  push dword ptr [ebp+36]
  mov ebx, -1
di_call:
  push dword ptr [ebp+32]
  push dword ptr [ebp+28]
  push dword ptr [ebp+24]
  push dword ptr [ebp+20]
  push dword ptr [ebp+16]
  push dword ptr [ebp+12]
  push dword ptr [ebp+8]
  mov ecx, dword ptr [ebp+8]
  mov ecx, dword ptr [ecx]
  call dword ptr [ecx+0x150]
  cmp ebx, -1
  je di_out
  mov ebx, eax
  call filt_off
  mov eax, ebx
di_out:
  lea esp, [ebp-12]
  pop edi
  pop esi
  pop ebx
  pop ebp
  ret 0x24

# smooth (bilinear) magnification while drawing scaled 2D; uses [ebp+8]=device, [ebp-16]=saved
filt_on:
  lea eax, [ebp-16]
  push eax
  push 5                              # D3DSAMP_MAGFILTER
  push 0
  push dword ptr [ebp+8]
  mov eax, dword ptr [ebp+8]
  mov eax, dword ptr [eax]
  call dword ptr [eax+0x110]          # GetSamplerState
  push 2                              # D3DTEXF_LINEAR
  push 5
  push 0
  push dword ptr [ebp+8]
  mov eax, dword ptr [ebp+8]
  mov eax, dword ptr [eax]
  call dword ptr [eax+0x114]          # SetSamplerState
  ret
filt_off:
  push dword ptr [ebp-16]
  push 5
  push 0
  push dword ptr [ebp+8]
  mov eax, dword ptr [ebp+8]
  mov eax, dword ptr [eax]
  call dword ptr [eax+0x114]
  ret

# ===================== SetViewport wrapper (this, pVP) =====================
my_setvp:
  push ebx
  push esi
  push edi
  mov esi, dword ptr [esp+20]         # pVP
  call calc_rect
  test eax, eax
  jz vp_pass
  mov eax, dword ptr [esi+16]
  mov dword ptr [vp_scaled+16], eax
  mov eax, dword ptr [esi+20]
  mov dword ptr [vp_scaled+20], eax
  mov ebx, dword ptr [rect_right]
  sub ebx, dword ptr [rect_left]      # rw
  mov edi, dword ptr [rect_bottom]
  sub edi, dword ptr [rect_top]       # rh
  mov eax, dword ptr [esi]
  mul ebx
  div dword ptr ds:0x6009e0
  add eax, dword ptr [rect_left]
  mov dword ptr [vp_scaled], eax
  mov eax, dword ptr [esi+4]
  mul edi
  div dword ptr ds:0x6009e4
  add eax, dword ptr [rect_top]
  mov dword ptr [vp_scaled+4], eax
  mov eax, dword ptr [esi+8]
  mul ebx
  div dword ptr ds:0x6009e0
  mov dword ptr [vp_scaled+8], eax
  mov eax, dword ptr [esi+12]
  mul edi
  div dword ptr ds:0x6009e4
  mov dword ptr [vp_scaled+12], eax
  mov dword ptr [vp_valid], 1
  mov esi, offset vp_scaled
vp_pass:
  mov ecx, dword ptr [esp+16]         # this
  push esi
  push ecx
  mov eax, dword ptr [ecx]
  call dword ptr [eax+0xbc]
  pop edi
  pop esi
  pop ebx
  ret 8

# black out only the bars around a pillar/letterboxed image (after Present)
clear_bars:
  call is_identity
  test eax, eax
  jnz cb_ret
  mov eax, dword ptr [rect_left]
  test eax, eax
  jz cb_letter
  # pillarbox: left and right bars
  mov dword ptr [bar_rects+0], 0
  mov dword ptr [bar_rects+4], 0
  mov dword ptr [bar_rects+8], eax
  mov eax, dword ptr [deskH]
  mov dword ptr [bar_rects+12], eax
  mov eax, dword ptr [rect_right]
  mov dword ptr [bar_rects+16], eax
  mov dword ptr [bar_rects+20], 0
  mov eax, dword ptr [deskW]
  mov dword ptr [bar_rects+24], eax
  mov eax, dword ptr [deskH]
  mov dword ptr [bar_rects+28], eax
  jmp cb_go
cb_letter:
  mov eax, dword ptr [rect_top]
  test eax, eax
  jz cb_ret
  mov dword ptr [bar_rects+0], 0
  mov dword ptr [bar_rects+4], 0
  mov ecx, dword ptr [deskW]
  mov dword ptr [bar_rects+8], ecx
  mov dword ptr [bar_rects+12], eax
  mov dword ptr [bar_rects+16], 0
  mov eax, dword ptr [rect_bottom]
  mov dword ptr [bar_rects+20], eax
  mov dword ptr [bar_rects+24], ecx
  mov eax, dword ptr [deskH]
  mov dword ptr [bar_rects+28], eax
cb_go:
  call get_dev
  test eax, eax
  jz cb_ret
  push esi
  mov esi, eax
  mov eax, dword ptr [deskW]
  mov dword ptr [vp_full+8], eax
  mov eax, dword ptr [deskH]
  mov dword ptr [vp_full+12], eax
  push offset vp_full
  push esi
  mov eax, dword ptr [esi]
  call dword ptr [eax+0xbc]           # SetViewport(full)
  push 0
  push 0x3f800000
  push 0xff000000
  push 1                              # D3DCLEAR_TARGET
  push offset bar_rects
  push 2
  push esi
  mov eax, dword ptr [esi]
  call dword ptr [eax+0xac]           # Clear(2 bar rects)
  cmp dword ptr [vp_valid], 0
  je cb_pop
  push offset vp_scaled
  push esi
  mov eax, dword ptr [esi]
  call dword ptr [eax+0xbc]
cb_pop:
  pop esi
cb_ret:
  ret

# ===================== software-canvas UI -> scaled texture =====================
ui_hook0:
  push ecx
  call is_identity
  pop ecx
  test eax, eax
  jnz ui_orig0
  push 0
  push ecx
  call ui_blit
  ret
ui_orig0:
  mov eax, dword ptr ds:0x31f3bc8
  jmp 0x40f625

ui_hook1:
  push ecx
  call is_identity
  pop ecx
  test eax, eax
  jnz ui_orig1
  push 1
  push ecx
  call ui_blit
  ret
ui_orig1:
  mov eax, dword ptr ds:0x31f3bc8
  jmp 0x40f825

.macro DEVCALL off
  mov eax, dword ptr [edi]
  call dword ptr [eax+\off]
.endm
.macro RS state, val
  push \val
  push \state
  push edi
  DEVCALL 0xe4
.endm
.macro TSS stage, type, val
  push \val
  push \type
  push \stage
  push edi
  DEVCALL 0x10c
.endm
.macro SS type, val
  push \val
  push \type
  push 0
  push edi
  DEVCALL 0x114
.endm

# stdcall ui_blit(entry, keyed)   entry: +0x14 x, +0x18 y, +0x1c w, +0x20 h
ui_blit:
  push ebp
  mov ebp, esp
  push ebx
  push esi
  push edi
  sub esp, 16                         # [ebp-16] beginscene hr
  call get_dev
  test eax, eax
  jz ub_out
  mov edi, eax
  call calc_rect
  test eax, eax
  jz ub_out
  cmp dword ptr ds:0x699b04, 0
  je ub_out
  # (re)create the UI texture when the game resolution changes
  mov eax, dword ptr ds:0x6009e0
  cmp eax, dword ptr [ui_texW]
  jne ub_create
  mov eax, dword ptr ds:0x6009e4
  cmp eax, dword ptr [ui_texH]
  jne ub_create
  cmp dword ptr [ui_tex], 0
  jne ub_have
ub_create:
  mov eax, dword ptr [ui_tex]
  test eax, eax
  jz 1f
  push eax
  mov eax, dword ptr [eax]
  call dword ptr [eax+8]
  mov dword ptr [ui_tex], 0
1:push 0
  push offset ui_tex
  push 1                              # D3DPOOL_MANAGED
  push 21                             # D3DFMT_A8R8G8B8
  push 0
  push 1
  push dword ptr ds:0x6009e4
  push dword ptr ds:0x6009e0
  push edi
  DEVCALL 0x5c                        # CreateTexture
  test eax, eax
  jne ub_fail
  mov eax, dword ptr ds:0x6009e0
  mov dword ptr [ui_texW], eax
  mov eax, dword ptr ds:0x6009e4
  mov dword ptr [ui_texH], eax
  # first upload: whole canvas, opaque
  mov dword ptr [ui_rect+0], 0
  mov dword ptr [ui_rect+4], 0
  mov eax, dword ptr [ui_texW]
  mov dword ptr [ui_rect+8], eax
  mov eax, dword ptr [ui_texH]
  mov dword ptr [ui_rect+12], eax
  push 0
  call ui_upload
ub_have:
  # dirty rect -> ui_rect (left, top, right, bottom), clamped
  mov esi, dword ptr [ebp+8]
  mov eax, dword ptr [esi+0x14]
  mov ecx, dword ptr [esi+0x18]
  mov edx, eax
  add edx, dword ptr [esi+0x1c]
  mov ebx, ecx
  add ebx, dword ptr [esi+0x20]
  test eax, eax
  jge 1f
  xor eax, eax
1:test ecx, ecx
  jge 2f
  xor ecx, ecx
2:cmp edx, dword ptr [ui_texW]
  jle 3f
  mov edx, dword ptr [ui_texW]
3:cmp ebx, dword ptr [ui_texH]
  jle 4f
  mov ebx, dword ptr [ui_texH]
4:cmp eax, edx
  jge ub_out
  cmp ecx, ebx
  jge ub_out
  mov dword ptr [ui_rect+0], eax
  mov dword ptr [ui_rect+4], ecx
  mov dword ptr [ui_rect+8], edx
  mov dword ptr [ui_rect+12], ebx
  push dword ptr [ebp+12]
  call ui_upload
  call ui_draw
  jmp ub_out
ub_fail:
  mov dword ptr [ui_tex], 0
  mov dword ptr [ui_texW], 0
ub_out:
  lea esp, [ebp-12]
  pop edi
  pop esi
  pop ebx
  pop ebp
  ret 8

# stdcall ui_upload(keyed): copy canvas ui_rect -> texture (edi = device)
ui_upload:
  push ebp
  mov ebp, esp
  push ebx
  push esi
  push edi
  mov eax, dword ptr ds:0x699b04
  push 0x10                           # D3DLOCK_READONLY
  push 0
  push offset ui_lr_c
  push eax
  mov eax, dword ptr [eax]
  call dword ptr [eax+0x34]           # canvas LockRect
  test eax, eax
  jne up_ret
  mov eax, dword ptr [ui_tex]
  push 0
  push offset ui_rect
  push offset ui_lr_t
  push 0
  push eax
  mov eax, dword ptr [eax]
  call dword ptr [eax+0x4c]           # texture LockRect
  test eax, eax
  jne up_unlock_c
  # esi = src row, edi = dst row
  mov eax, dword ptr [ui_rect+4]
  imul eax, dword ptr [ui_lr_c]
  mov esi, dword ptr [ui_rect+0]
  lea esi, [eax+esi*2]
  add esi, dword ptr [ui_lr_c+4]
  mov edi, dword ptr [ui_lr_t+4]
  mov ecx, dword ptr [ui_rect+12]
  sub ecx, dword ptr [ui_rect+4]      # rows
up_row:
  push ecx
  push esi
  push edi
  mov ecx, dword ptr [ui_rect+8]
  sub ecx, dword ptr [ui_rect+0]      # cols
up_px:
  movzx eax, word ptr [esi]
  add esi, 2
  cmp dword ptr [ebp+8], 0
  je up_conv
  cmp eax, 0xa81f
  jne up_conv
  mov dword ptr [edi], 0
  jmp up_next
up_conv:
  mov ebx, eax
  mov edx, eax
  and ebx, 0xf800
  and edx, 0x7e0
  shl ebx, 3
  or ebx, edx
  and eax, 0x1f
  shl ebx, 2
  or ebx, eax
  shl ebx, 3
  or ebx, 0xff000000
  mov dword ptr [edi], ebx
up_next:
  add edi, 4
  dec ecx
  jnz up_px
  pop edi
  pop esi
  pop ecx
  add esi, dword ptr [ui_lr_c]
  add edi, dword ptr [ui_lr_t]
  dec ecx
  jnz up_row
  mov eax, dword ptr [ui_tex]
  push 0
  push eax
  mov eax, dword ptr [eax]
  call dword ptr [eax+0x50]           # texture UnlockRect
up_unlock_c:
  mov eax, dword ptr ds:0x699b04
  push eax
  mov eax, dword ptr [eax]
  call dword ptr [eax+0x38]           # canvas UnlockRect
up_ret:
  pop edi
  pop esi
  pop ebx
  pop ebp
  ret 4

# fill one float: st0 = rect_origin + v * scale - 0.5  (v int in eax)
# draw ui_rect of the texture, scaled into the game-image rect (edi = device, [ebp+12]=keyed of ui_blit)
ui_draw:
  # scale factors
  mov eax, dword ptr [rect_right]
  sub eax, dword ptr [rect_left]
  push eax
  fild dword ptr [esp]
  fidiv dword ptr [ui_texW]
  fstp dword ptr [sx]
  mov eax, dword ptr [rect_bottom]
  sub eax, dword ptr [rect_top]
  mov dword ptr [esp], eax
  fild dword ptr [esp]
  fidiv dword ptr [ui_texH]
  fstp dword ptr [sy]
  fild dword ptr [rect_left]
  fsub dword ptr [half]
  fstp dword ptr [fleft]
  fild dword ptr [rect_top]
  fsub dword ptr [half]
  fstp dword ptr [ftop]
  add esp, 4
  # x0,x1 -> verts
  fild dword ptr [ui_rect+0]
  fmul dword ptr [sx]
  fadd dword ptr [fleft]
  fst dword ptr [ui_verts+0]
  fstp dword ptr [ui_verts+48]
  fild dword ptr [ui_rect+8]
  fmul dword ptr [sx]
  fadd dword ptr [fleft]
  fst dword ptr [ui_verts+24]
  fstp dword ptr [ui_verts+72]
  fild dword ptr [ui_rect+4]
  fmul dword ptr [sy]
  fadd dword ptr [ftop]
  fst dword ptr [ui_verts+4]
  fstp dword ptr [ui_verts+28]
  fild dword ptr [ui_rect+12]
  fmul dword ptr [sy]
  fadd dword ptr [ftop]
  fst dword ptr [ui_verts+52]
  fstp dword ptr [ui_verts+76]
  # u,v
  fild dword ptr [ui_rect+0]
  fidiv dword ptr [ui_texW]
  fst dword ptr [ui_verts+16]
  fstp dword ptr [ui_verts+64]
  fild dword ptr [ui_rect+8]
  fidiv dword ptr [ui_texW]
  fst dword ptr [ui_verts+40]
  fstp dword ptr [ui_verts+88]
  fild dword ptr [ui_rect+4]
  fidiv dword ptr [ui_texH]
  fst dword ptr [ui_verts+20]
  fstp dword ptr [ui_verts+44]
  fild dword ptr [ui_rect+12]
  fidiv dword ptr [ui_texH]
  fst dword ptr [ui_verts+68]
  fstp dword ptr [ui_verts+92]
  # z = 0, rhw = 1
  xor eax, eax
  mov dword ptr [ui_verts+8], eax
  mov dword ptr [ui_verts+32], eax
  mov dword ptr [ui_verts+56], eax
  mov dword ptr [ui_verts+80], eax
  mov eax, 0x3f800000
  mov dword ptr [ui_verts+12], eax
  mov dword ptr [ui_verts+36], eax
  mov dword ptr [ui_verts+60], eax
  mov dword ptr [ui_verts+84], eax
  # scene + saved state
  push edi
  DEVCALL 0xa4                        # BeginScene
  mov dword ptr [ebp-16], eax
  cmp dword ptr [ui_sb], 0
  jne 1f
  push offset ui_sb
  push 1                              # D3DSBT_ALL
  push edi
  DEVCALL 0xec                        # CreateStateBlock
  test eax, eax
  je 1f
  mov dword ptr [ui_sb], 0
1:mov eax, dword ptr [ui_sb]
  test eax, eax
  jz 2f
  push eax
  mov eax, dword ptr [eax]
  call dword ptr [eax+0x10]           # Capture
2:push dword ptr [ui_tex]
  push 0
  push edi
  DEVCALL 0x104                       # SetTexture(0, ui)
  push 0
  push 1
  push edi
  DEVCALL 0x104                       # SetTexture(1, NULL)
  push 0
  push edi
  DEVCALL 0x170                       # SetVertexShader(NULL)
  push 0
  push edi
  DEVCALL 0x1ac                       # SetPixelShader(NULL)
  push 0x104
  push edi
  DEVCALL 0x164                       # SetFVF(XYZRHW|TEX1)
  RS 7, 0                             # ZENABLE
  RS 14, 0                            # ZWRITEENABLE
  RS 15, 0                            # ALPHATESTENABLE
  RS 22, 1                            # CULLMODE none
  RS 28, 0                            # FOGENABLE
  RS 52, 0                            # STENCILENABLE
  RS 168, 15                          # COLORWRITEENABLE
  RS 174, 0                           # SCISSORTESTENABLE
  RS 19, 5                            # SRCBLEND srcalpha
  RS 20, 6                            # DESTBLEND invsrcalpha
  mov eax, dword ptr [ebp+12]         # keyed -> blend
  push eax
  push 27                             # ALPHABLENDENABLE
  push edi
  DEVCALL 0xe4
  TSS 0, 1, 2                         # COLOROP selectarg1
  TSS 0, 2, 2                         # COLORARG1 texture
  TSS 0, 4, 2                         # ALPHAOP selectarg1
  TSS 0, 5, 2                         # ALPHAARG1 texture
  TSS 1, 1, 1                         # stage1 COLOROP disable
  TSS 1, 4, 1                         # stage1 ALPHAOP disable
  SS 1, 3                             # ADDRESSU clamp
  SS 2, 3                             # ADDRESSV clamp
  SS 5, 2                             # MAGFILTER linear
  SS 6, 2                             # MINFILTER linear
  SS 7, 0                             # MIPFILTER none
  push 24
  push offset ui_verts
  push 2
  push 5                              # TRIANGLESTRIP
  push edi
  DEVCALL 0x14c                       # DrawPrimitiveUP
  mov eax, dword ptr [ui_sb]
  test eax, eax
  jz 3f
  push eax
  mov eax, dword ptr [eax]
  call dword ptr [eax+0x14]           # Apply
3:cmp dword ptr [ebp-16], 0
  jne 4f
  push edi
  DEVCALL 0xa8                        # EndScene
4:ret

# ===================== hooks =====================
dpi_hook:
  push offset s_user32
  call dword ptr ds:0x5d41d0          # GetModuleHandleA
  test eax, eax
  jz dpi_skip
  push offset s_dpi
  push eax
  call dword ptr ds:0x5d409c          # GetProcAddress
  test eax, eax
  jz dpi_skip
  call eax
dpi_skip:
  mov ecx, dword ptr ds:0x6009e4
  jmp 0x551b41

# CreateDevice present params: backbuffer = desktop size (edx = IDirect3D9*, ecx = hwnd)
cd_size_hook:
  push ecx
  mov ecx, dword ptr [esi+4]
  call ensure_desk
  pop ecx
  mov eax, dword ptr [deskW]
  test eax, eax
  jnz 1f
  mov eax, dword ptr [esi+0x20]
1:mov dword ptr [esp+0x10], eax
  mov eax, dword ptr [deskH]
  test eax, eax
  jnz 2f
  mov eax, dword ptr [esi+0x24]
2:mov dword ptr [esp+0x14], eax
  jmp 0x4136fd

# Reset present params: backbuffer = desktop size
reset_size_hook:
  mov eax, dword ptr [deskW]
  mov ecx, dword ptr [deskH]
  test eax, eax
  jz 1f
  test ecx, ecx
  jnz 2f
1:mov eax, dword ptr [esi+0x20]
  mov ecx, dword ptr [esi+0x24]
2:mov edx, dword ptr [esi+0xc]
  add esp, 0x18
  mov dword ptr [vp_valid], 0
  push eax
  push ecx
  push edx
  mov eax, dword ptr [ui_sb]
  test eax, eax
  jz 1f
  push eax
  mov eax, dword ptr [eax]
  call dword ptr [eax+8]
  mov dword ptr [ui_sb], 0
1:pop edx
  pop ecx
  pop eax
  jmp 0x4138a0

# after CreateDevice: borderless window over the whole desktop
move_hook:
  mov eax, dword ptr [esi+0x28]
  mov edx, dword ptr [eax]
  mov ecx, dword ptr [esi+4]
  call ensure_desk
  mov eax, dword ptr [deskW]
  test eax, eax
  jnz 1f
  mov eax, dword ptr [esi+0x20]
  mov dword ptr [deskW], eax
  mov eax, dword ptr [esi+0x24]
  mov dword ptr [deskH], eax
1:push 1
  push dword ptr [deskH]
  push dword ptr [deskW]
  push 0
  push 0
  push dword ptr ds:0x6b019c
  call dword ptr ds:0x5d41e0          # MoveWindow
  jmp 0x413755

# frame Present (esi = app, ebx = 0)
present_hook:
  mov esi, dword ptr [esi+4]
  push ebx
  push ebx
  push ebx
  push ebx
  push esi
  mov eax, dword ptr [esi]
  call dword ptr [eax+0x44]
  push eax
  call clear_bars
  pop eax
  jmp 0x40e48f

# video frame StretchRect: put it in the game-image rect (eax=app ptr, edx=dest surface)
stretch_hook:
  push eax
  push edx
  call calc_rect
  mov ecx, eax
  pop edx
  pop eax
  push 0                              # filter
  push ecx                            # pDestRect
  mov eax, dword ptr [eax+4]
  jmp 0x4478dc

# WM_MOUSEMOVE: desktop pixels -> game pixels (ebx = lParam)
mouse_hook:
  movsx ecx, bx
  mov edx, ebx
  sar edx, 16
  push edx
  push ecx
  call calc_rect
  pop ecx
  pop edx
  test eax, eax
  jz mouse_pass
  mov eax, ecx
  sub eax, dword ptr [rect_left]
  imul eax, dword ptr ds:0x6009e0
  mov ecx, dword ptr [rect_right]
  sub ecx, dword ptr [rect_left]
  push edx
  cdq
  idiv ecx
  pop edx
  mov esi, eax
  mov eax, edx
  sub eax, dword ptr [rect_top]
  imul eax, dword ptr ds:0x6009e4
  mov ecx, dword ptr [rect_bottom]
  sub ecx, dword ptr [rect_top]
  cdq
  idiv ecx
  mov edx, eax
  mov ecx, esi
mouse_pass:
  mov dword ptr [fromOS], 1
  call 0x49e0a0
  mov dword ptr [fromOS], 0
  jmp 0x5519b9

# inside 0x49e0a0: move the real cursor only when the game warps it
setcur_hook:
  cmp dword ptr [fromOS], 0
  jne setcur_out
  test esi, esi
  jz setcur_out
  mov eax, dword ptr [esi+4]
  test eax, eax
  jz setcur_out
  push eax
  call calc_rect
  test eax, eax
  jz setcur_raw
  mov eax, dword ptr ds:0xa7aa40
  mov ecx, dword ptr [rect_right]
  sub ecx, dword ptr [rect_left]
  imul eax, ecx
  cdq
  idiv dword ptr ds:0x6009e0
  add eax, dword ptr [rect_left]
  push eax
  mov eax, dword ptr ds:0xa7aa44
  mov ecx, dword ptr [rect_bottom]
  sub ecx, dword ptr [rect_top]
  imul eax, ecx
  cdq
  idiv dword ptr ds:0x6009e4
  add eax, dword ptr [rect_top]
  mov edx, eax
  pop ecx
  jmp setcur_call
setcur_raw:
  mov ecx, dword ptr ds:0xa7aa40
  mov edx, dword ptr ds:0xa7aa44
setcur_call:
  pop eax
  push 1
  push edx
  push ecx
  push eax
  mov ecx, dword ptr [eax]
  call dword ptr [ecx+0x2c]
setcur_out:
  jmp 0x49e12a

clip_hook:
  mov eax, dword ptr [deskW]
  mov ecx, dword ptr [deskH]
  test eax, eax
  jnz clip_ok
  mov eax, dword ptr ds:0x31f3bc0
  mov ecx, dword ptr ds:0x31f3bc4
clip_ok:
  jmp 0x49e18c

# display-mode lookup failed: accept the requested size anyway (we never change modes)
mode_accept:
  mov dword ptr [ecx+0x1c], 0
  mov eax, dword ptr ds:0x6009e0
  mov dword ptr [ecx+0x20], eax
  mov eax, dword ptr ds:0x6009e4
  mov dword ptr [ecx+0x24], eax
  mov eax, 1
  ret

# window proc: WM_CLOSE (taskbar X / Alt+F4) -> clean up input settings and quit the whole game
close_hook:
  cmp esi, 0x10
  je do_close
  cmp esi, 0x20
  ja 0x55198d
  jmp 0x5518b8
do_close:
  call 0x436dd0                       # DirectInput kill (restores accessibility keys)
  call 0x436d10                       # RestoreMouse (Windows mouse settings)
  push 0
  call dword ptr ds:0x5d4204          # ClipCursor(NULL)
  push 0
  call dword ptr ds:0x5d40c4          # ExitProcess(0)
