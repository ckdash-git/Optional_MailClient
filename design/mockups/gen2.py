# Round 2 design comps: 4 screens x 3 directions. Static HTML rendered by Chromium; not app code.
ACC=[("Work","alice@corp.test",9,"A"),("Studio","alice@studio.example",3,"S")]
REC=[("Sam Okafor","Lunch tomorrow?","1:40 PM",True,"Work"),("Marco Rossi","Re: Release checklist","9:20 AM",True,"Work"),("Nora Lindqvist","Invoice 1042 approved","Yesterday",True,"Studio"),("Priya Nair","Design review moved to Thursday","Yesterday",False,"Studio")]
INB=[("Sam Okafor","Lunch tomorrow?","Are you free for lunch around 12:30? New place near the station.","1:40 PM",True),
("Ops Alerts","Backup completed","Nightly backup finished in 4m12s. 0 errors.","11:20 AM",False),
("Marco Rossi","Re: Release checklist","Looks good. Do we ship the push relay in 1.0 or 1.1?","9:20 AM",True),
("Billing","Your invoice for October","Invoice #20481 is ready. Amount due 42.00 EUR.","Yesterday",False),
("Priya Nair","Design review moved to Thursday","We moved the review to Thursday 15:00 so Marco can join.","Yesterday",True)]
CON=[("Lena Fischer","Finance · Corp"),("Marco Rossi","Engineer · Studio North"),("Nora Lindqvist","Editor · News Co"),("Priya Nair","Design lead · Studio North"),("Sam Okafor","Account manager · Partner Ltd")]
TABS=["Mail","Calendar","Contacts","Settings"]
IC={"Mail":'<rect x="3" y="6" width="18" height="12" rx="2"/><path d="M4 8l8 6 8-6"/>',"Calendar":'<rect x="3.5" y="5" width="17" height="15" rx="2.5"/><path d="M3.5 10h17M8 3v4M16 3v4"/>',"Contacts":'<circle cx="12" cy="9" r="3.5"/><path d="M5 20c1-4 4-5 7-5s6 1 7 5"/>',"Settings":'<circle cx="12" cy="12" r="3"/><path d="M12 3v3M12 18v3M3 12h3M18 12h3"/>'}
def tab(on): return '<div class="tabbar">'+''.join(f'<div class="tab {"on" if t==on else ""}"><svg viewBox="0 0 24 24" width="24" height="24" fill="none" stroke="currentColor" stroke-width="1.8">{IC[t]}</svg><span>{t}</span></div>' for t in TABS)+'</div>'
st='<div class="status"><b>9:41</b><span>●●● ▮</span></div>'
def mailboxes():
    cards=''.join(f'<div class="acc c{i}"><div class="an">{n}</div><div class="ae">{e}</div><div class="au"><b>{u}</b> unread</div><div class="ap"><i></i>Instant</div></div>' for i,(n,e,u,_) in enumerate(ACC))
    rec=''.join(f'<div class="rr"><div class="ch c{0 if a=="Work" else 1}"></div><div class="rb"><div class="r1"><span class="{"b" if u else ""}">{n}</span><em>{t}</em></div><div class="sj">{s}</div></div></div>' for n,s,t,u,a in REC)
    return f'<div class="scr">{st}<div class="hdr"><div class="ttl">Mailboxes</div></div><div class="accs">{cards}</div><div class="sec">Recents <small>all accounts</small></div><div class="list">{rec}</div>{tab("Mail")}</div>'
def inbox():
    chips=''.join(f'<span class="chip {"on" if i==0 else ""}">{c}</span>' for i,c in enumerate(["All","Unread · 9","Starred","Attachments"]))
    rows=''.join(f'<div class="row {"unread" if u else ""}"><div class="av">{n[0]}</div><div class="rb"><div class="r1"><span class="nm">{n}</span><em>{t}</em></div><div class="sj">{s}</div><div class="pv">{p}</div></div></div>' for n,s,p,t,u in INB)
    return f'<div class="scr">{st}<div class="nav"><span>‹ Mailboxes</span><span>Edit</span></div><div class="hdr"><div class="ttl">Work</div><div class="sub">alice@corp.test · push live</div></div><div class="chips">{chips}</div><div class="list">{rows}</div><div class="fab">✎ Compose</div>{tab("Mail")}</div>'
def compose():
    return f'''<div class="scr">{st}<div class="nav"><span>Cancel</span><b>New message</b><span class="send">Send</span></div>
<div class="fld"><small>From</small><span>alice@corp.test</span></div><div class="fld"><small>To</small><span class="pill">Priya Nair</span><span class="pill">Sam Okafor</span></div>
<div class="fld"><small>Subject</small><span><b>Re: Design review moved to Thursday</b></span></div>
<div class="body"><p>Thursday 15:00 works for me. See you there!</p><p class="q">On Mon, Priya Nair wrote:<br>&gt; We moved the design review to Thursday 15:00 so Marco can join.</p></div>
<div class="kb"><span>📎 Attach</span><span>Cc/Bcc</span><span>Aa</span></div></div>'''
def contacts():
    rows=''.join(f'<div class="row"><div class="av">{n[0]}</div><div class="rb"><div class="nm2">{n}</div><div class="pv">{r}</div></div></div>' for n,r in CON)
    return f'<div class="scr">{st}<div class="hdr"><div class="ttl">Contacts</div></div><div class="search">⌕ &nbsp;Search contacts</div><div class="list">{rows}</div>{tab("Contacts")}</div>'
BASE='''*{box-sizing:border-box;margin:0}body{font-family:-apple-system,"SF Pro Text",Roboto,"Helvetica Neue",Arial,sans-serif;background:var(--bg);padding:32px;display:flex;gap:30px;justify-content:center;color:var(--ink)}
.phone{width:390px;height:844px;border-radius:52px;background:#0b0b0c;padding:11px;box-shadow:0 30px 60px rgba(0,0,0,.25);flex:none}.scr{width:100%;height:100%;border-radius:42px;overflow:hidden;position:relative;background:var(--ground);display:flex;flex-direction:column}
.status{height:50px;padding:16px 28px 0;display:flex;justify-content:space-between;font-size:15px}.hdr{padding:2px 20px 10px}.ttl{font-size:34px;font-weight:800;letter-spacing:-.5px}.sub{font-size:13px;color:var(--mute);margin-top:2px}
.nav{display:flex;justify-content:space-between;padding:6px 20px;color:var(--tint);font-size:17px}.nav b{color:var(--ink);font-size:17px}.list{flex:1;overflow:hidden}
.tabbar{height:84px;display:flex;justify-content:space-around;padding-top:10px;border-top:1px solid var(--line);background:var(--tabbg)}.tab{display:flex;flex-direction:column;align-items:center;gap:3px;font-size:10.5px;color:var(--mute);width:70px}.tab.on{color:var(--tint);font-weight:600}
.row,.rr{display:flex;gap:12px;padding:12px 20px}.av{width:42px;height:42px;border-radius:50%;display:grid;place-items:center;font-weight:600;background:var(--avbg);color:var(--avfg);flex:none}.rb{flex:1;min-width:0}.r1{display:flex;justify-content:space-between;font-size:15px}.r1 em,.tm{font-style:normal;font-size:12.5px;color:var(--mute)}
.sj{font-size:14.5px;white-space:nowrap;overflow:hidden;text-overflow:ellipsis}.pv{font-size:13.5px;color:var(--mute);margin-top:2px;white-space:nowrap;overflow:hidden;text-overflow:ellipsis}.unread .nm,.unread .sj,.b{font-weight:700}.nm2{font-size:16px;font-weight:600}
.chips{display:flex;gap:8px;padding:2px 20px 10px;overflow:hidden}.chip{padding:7px 13px;border-radius:99px;font-size:13px;background:var(--chip);white-space:nowrap}.chip.on{background:var(--tint);color:#fff}
.fab{position:absolute;right:18px;bottom:100px;padding:14px 20px;border-radius:99px;background:var(--tint);color:#fff;font-weight:600;font-size:15px;box-shadow:0 8px 20px rgba(0,0,0,.25)}
.accs{display:flex;gap:12px;padding:4px 20px 6px}.acc{flex:1;border-radius:var(--rad);padding:16px;display:flex;flex-direction:column;gap:3px}.an{font-size:20px;font-weight:800}.ae{font-size:11.5px;opacity:.75;overflow:hidden;text-overflow:ellipsis;white-space:nowrap}.au{margin-top:14px;font-size:13px}.au b{font-size:30px;display:block;line-height:1}.ap{margin-top:10px;font-size:11.5px;display:flex;align-items:center;gap:6px}.ap i{width:7px;height:7px;border-radius:50%;background:currentColor}
.sec{padding:16px 20px 4px;font-size:20px;font-weight:700}.sec small{font-size:12px;font-weight:500;color:var(--mute);margin-left:6px}.ch{width:5px;border-radius:3px}.rr{padding:10px 20px}
.fld{display:flex;gap:10px;align-items:center;padding:12px 20px;border-bottom:1px solid var(--line);font-size:15px;flex-wrap:wrap}.fld small{color:var(--mute);width:56px}.pill{background:var(--chip);padding:5px 11px;border-radius:99px}.send{font-weight:700}
.body{padding:16px 20px;font-size:16.5px;line-height:1.5;flex:1}.q{color:var(--mute);margin-top:18px;font-size:14.5px}.kb{padding:12px 20px 28px;display:flex;gap:22px;color:var(--tint);font-size:15px;border-top:1px solid var(--line)}
.search{margin:0 20px 8px;padding:10px 14px;border-radius:12px;background:var(--chip);color:var(--mute);font-size:15px}
'''
T={
'R1':dict(n='R1 · Calm hierarchy (native, mailboxes-first)',v='--bg:#E6E8EC;--ink:#111418;--ground:#F2F3F5;--line:#E1E3E8;--tabbg:#fff;--mute:#6A7180;--tint:#0E7C86;--chip:#E4E7EC;--avbg:#D9E7E8;--avfg:#0B5C64;--rad:18px',
 x='.acc.c0{background:#fff;box-shadow:0 1px 2px rgba(0,0,0,.06)}.acc.c1{background:#fff}.ap{color:#0E7C86}.row{background:#fff;margin:0 16px 8px;border-radius:16px;padding:12px 14px}.rr{background:#fff;margin:0 16px 6px;border-radius:14px}.unread .av{background:#0E7C86;color:#fff}.c0{--cc:#0E7C86}.ch.c0{background:#0E7C86}.ch.c1{background:#E0894A}.search,.chip{border-radius:12px}'),
'R2':dict(n='R2 · Soft cards',v='--bg:#E5E7F2;--ink:#14172B;--ground:#EEF0F8;--line:#DADDEB;--tabbg:#fff;--mute:#6B7090;--tint:#4F46E5;--chip:#fff;--avbg:#E0E0FA;--avfg:#3730A3;--rad:24px',
 x='.row{background:#fff;margin:0 14px 10px;border-radius:22px;padding:14px 16px;box-shadow:0 6px 16px rgba(60,60,130,.10)}.rr{background:#fff;margin:0 14px 8px;border-radius:18px;box-shadow:0 4px 12px rgba(60,60,130,.08)}.acc.c0{background:linear-gradient(160deg,#6D63F0,#4F46E5);color:#fff}.acc.c1{background:#fff;box-shadow:0 6px 16px rgba(60,60,130,.10)}.ap{color:inherit}.unread .nm{color:#14172B}.unread .av{background:#4F46E5;color:#fff}.ch.c0{background:#4F46E5}.ch.c1{background:#9AA0E8}.chip{box-shadow:0 2px 6px rgba(60,60,130,.10)}.chip.on{box-shadow:none}.fab{border-radius:20px}'),
'R3':dict(n='R3 · Colour-blocks (A, extended)',v='--bg:#E4E8F1;--ink:#0F1B3D;--ground:#F4F6FA;--line:#D9DEEA;--tabbg:#fff;--mute:#5C6788;--tint:#1B3A8C;--chip:#E3E8F5;--avbg:#E3E8F5;--avfg:#1B3A8C;--rad:14px',
 x='.status,.hdr{background:#1B3A8C;color:#fff}.hdr{padding-bottom:16px;border-radius:0 0 28px 0;margin-bottom:8px}.hdr .sub{color:#C9D5FF}.acc.c0{background:#E8452C;color:#fff}.acc.c1{background:#F5B82E;color:#0F1B3D}.ap{color:inherit}.row{border-bottom:1px solid #E6EAF3}.unread .av{background:#E8452C;color:#fff;border-radius:10px}.ch.c0{background:#E8452C}.ch.c1{background:#F5B82E}.rr{border-bottom:1px solid #E6EAF3}.nav{background:#F4F6FA}'),
}
def page(k):
    t=T[k]; ph=lambda s:f'<div class="phone">{s}</div>'
    return f'<!doctype html><meta charset=utf-8><title>{t["n"]}</title><style>:root{{{t["v"]}}}{BASE}{t["x"]}</style><body>'+ph(mailboxes())+ph(inbox())+ph(compose())+ph(contacts())
for k in T: open(f'round2-{k}.html','w').write(page(k))
