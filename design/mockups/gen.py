# Static design comps (HTML) for three directions. Rendered with Chromium; not app code.
MAIL = [
 ("Sam Okafor","Lunch tomorrow?","Are you free for lunch around 12:30? New place near the station.","1:40 PM",True,False,"S"),
 ("Ops Alerts","Backup completed","Nightly backup finished in 4m12s. 0 errors.","11:20 AM",False,False,"O"),
 ("Marco Rossi","Re: Release checklist","Looks good. Do we ship the push relay in 1.0 or 1.1?","9:20 AM",True,True,"M"),
 ("Billing","Your invoice for October","Invoice #20481 is ready. Amount due 42.00 EUR.","Yesterday",False,False,"B"),
 ("Priya Nair","Design review moved to Thursday","We moved the review to Thursday 15:00 so Marco can join.","Yesterday",True,False,"P"),
 ("Lena Fischer","Q4 budget sheet","Attached is the updated sheet. Please check row 14.","Mon",False,False,"L"),
]
EVENTS = [("09:30","09:45","Team standup","Room 2"),("14:00","15:00","Design review","Zoom"),("16:30","17:00","1:1 with Priya",""),]
EV2 = [("11:00","11:30","Budget check-in",""),("15:00","16:30","Design review (moved)","Studio, 3rd floor")]
TABS=[("Mail","m"),("Calendar","c"),("Contacts","p"),("Settings","s")]
def ico(k,active=False):
    st='currentColor'
    d={"m":'<rect x="3" y="6" width="18" height="12" rx="2" fill="none" stroke="%s" stroke-width="1.8"/><path d="M4 8l8 6 8-6" fill="none" stroke="%s" stroke-width="1.8"/>',
       "c":'<rect x="3.5" y="5" width="17" height="15" rx="2.5" fill="none" stroke="%s" stroke-width="1.8"/><path d="M3.5 10h17M8 3v4M16 3v4" stroke="%s" stroke-width="1.8" fill="none"/>',
       "p":'<circle cx="12" cy="9" r="3.5" fill="none" stroke="%s" stroke-width="1.8"/><path d="M5 20c1-4 4-5 7-5s6 1 7 5" fill="none" stroke="%s" stroke-width="1.8"/>',
       "s":'<circle cx="12" cy="12" r="3" fill="none" stroke="%s" stroke-width="1.8"/><path d="M12 3v3M12 18v3M3 12h3M18 12h3M5.6 5.6l2.1 2.1M16.3 16.3l2.1 2.1M18.4 5.6l-2.1 2.1M7.7 16.3l-2.1 2.1" stroke="%s" stroke-width="1.8"/>'}[k]
    return '<svg viewBox="0 0 24 24" width="24" height="24">'+(d%(st,st))+'</svg>'
def tabbar(active):
    return '<div class="tabbar">'+''.join(f'<div class="tab {"on" if n==active else ""}">{ico(k)}<span>{n}</span></div>' for n,k in TABS)+'</div>'
def status(): return '<div class="status"><b>9:41</b><span>●●● ▮</span></div>'
def inbox(theme):
    rows=''
    for i,(n,s,p,t,unread,star,ini) in enumerate(MAIL):
        rows+=f'<div class="row {"unread" if unread else ""}"><div class="av a{i%4}">{ini}</div><div class="rb"><div class="r1"><span class="nm">{n}</span><span class="tm">{t}</span></div><div class="sj">{s}</div><div class="pv">{p}</div></div>{"<i class=dot></i>" if unread else ""}</div>'
    hdr={'A':'<div class="hdr"><div class="ttl">Inbox</div><div class="sub">alice@corp.test · <b>Instant</b></div></div>',
         'B':'<div class="hdr"><div class="ttl">Inbox</div><div class="sub">alice@corp.test · push live</div></div>',
         'C':'<div class="hdr"><div class="ttl">Inbox</div></div>'}[theme]
    return f'<div class="scr">{status()}{hdr}<div class="list">{rows}</div>{tabbar("Mail")}</div>'
def message(theme):
    return f'''<div class="scr">{status()}<div class="nav"><span class="back">‹ Inbox</span><span class="acts">☆ &nbsp; ⌫</span></div>
<div class="mh"><div class="msj">Design review moved to Thursday</div><div class="mfrom"><div class="av a1">P</div><div><b>Priya Nair</b><div class="mm">priya@studio.example · Yesterday</div></div></div></div>
<div class="banner">Remote images were blocked to protect your privacy.</div>
<div class="body"><p>Hi Alice,</p><p>We moved the design review to Thursday 15:00 so Marco can join.</p><p>Agenda: <u>studio.example/review</u></p><p>Thanks,<br>Priya</p></div>
<div class="actions"><span>Reply</span><span>Reply all</span><span>Forward</span></div></div>'''
def calendar(theme):
    days=''
    for d,evs,lab in [("Today · Tue 20",EVENTS,"t"),("Tomorrow · Wed 21",EV2,"")]:
        days+=f'<div class="dh {lab}">{d}</div>'
        for a,b,t,l in evs: days+=f'<div class="ev"><div class="et"><b>{a}</b><span>{b}</span></div><div class="ec"></div><div class="eb"><div class="en">{t}</div><div class="el">{l}</div></div></div>'
    strip=''.join(f'<div class="dd {"now" if i==2 else ""}"><small>{w}</small><b>{n}</b>{"<i></i>" if i in (2,3,5) else ""}</div>' for i,(w,n) in enumerate(zip("MTWTFSS",[19,20,21,22,23,24,25])))
    return f'<div class="scr">{status()}<div class="hdr"><div class="ttl">Calendar</div><div class="sub">October 2026</div></div><div class="strip">{strip}</div><div class="list">{days}</div>{tabbar("Calendar")}</div>'
CSS_BASE='''*{box-sizing:border-box;margin:0}body{font-family:-apple-system,"SF Pro Text","Segoe UI",Roboto,"Helvetica Neue",Arial,sans-serif;background:%BG%;padding:36px;display:flex;gap:36px;justify-content:center;color:%INK%}
.phone{width:390px;height:844px;border-radius:52px;background:#0b0b0c;padding:11px;box-shadow:0 30px 60px rgba(0,0,0,.28)}
.scr{width:100%;height:100%;border-radius:42px;overflow:hidden;position:relative;background:%GROUND%;display:flex;flex-direction:column}
.status{height:50px;padding:16px 28px 0;display:flex;justify-content:space-between;font-size:15px}
.list{flex:1;overflow:hidden}.tabbar{height:84px;display:flex;justify-content:space-around;padding-top:10px;border-top:1px solid %LINE%;background:%TABBG%}
.tab{display:flex;flex-direction:column;align-items:center;gap:3px;font-size:10.5px;color:%MUTE%;width:70px}.tab.on{color:%TINT%;font-weight:600}
.row{display:flex;gap:12px;padding:12px 18px;position:relative}.av{width:40px;height:40px;border-radius:50%;display:grid;place-items:center;font-weight:600;font-size:15px;flex:none}
.rb{flex:1;min-width:0}.r1{display:flex;justify-content:space-between;font-size:15px}.tm{font-size:12.5px;color:%MUTE%}
.sj{font-size:14.5px;margin-top:1px;white-space:nowrap;overflow:hidden;text-overflow:ellipsis}.pv{font-size:13.5px;color:%MUTE%;margin-top:2px;white-space:nowrap;overflow:hidden;text-overflow:ellipsis}
.row.unread .nm,.row.unread .sj{font-weight:650}.nav{display:flex;justify-content:space-between;padding:6px 18px;color:%TINT%;font-size:17px}
.mh{padding:10px 20px}.msj{font-size:24px;font-weight:700;line-height:1.2;margin-bottom:14px}.mfrom{display:flex;gap:12px;align-items:center;font-size:15px}.mm{font-size:12.5px;color:%MUTE%}
.banner{margin:12px 20px;padding:10px 12px;border-radius:10px;font-size:12.5px;background:%BANNER%;color:%INK%}.body{padding:6px 20px;font-size:16.5px;line-height:1.5}.body p{margin-bottom:12px}u{color:%TINT%}
.actions{position:absolute;bottom:24px;left:16px;right:16px;display:flex;gap:8px}.actions span{flex:1;text-align:center;padding:12px 0;border-radius:%RAD%;font-size:15px;font-weight:600;border:1.5px solid %TINT%;color:%TINT%}
.strip{display:flex;justify-content:space-around;padding:6px 8px 12px}.dd{display:flex;flex-direction:column;align-items:center;width:44px;padding:6px 0;gap:3px;border-radius:%RAD%;position:relative}.dd small{font-size:11px;color:%MUTE%}.dd b{font-size:17px}.dd i{width:5px;height:5px;border-radius:50%;background:%TINT%}
.dh{padding:14px 20px 6px;font-size:13px;color:%MUTE%;font-weight:600}.ev{display:flex;gap:12px;padding:8px 20px;align-items:stretch}.et{width:52px;display:flex;flex-direction:column;font-size:14px}.et span{font-size:12.5px;color:%MUTE%}.eb .en{font-size:16px;font-weight:600}.eb .el{font-size:13px;color:%MUTE%}
.hdr{padding:2px 20px 10px}.ttl{font-size:34px;font-weight:800;letter-spacing:-.5px}.sub{font-size:13px;color:%MUTE%;margin-top:2px}
.dot{position:absolute;right:16px;top:30px;width:9px;height:9px}
'''
THEMES={
'A':dict(NAME='A · Colour-blocks',BG='#E4E8F1',INK='#0F1B3D',GROUND='#F4F6FA',LINE='#D9DEEA',TABBG='#FFFFFF',MUTE='#5C6788',TINT='#1B3A8C',BANNER='#FFF1C7',RAD='12px',
 extra='''.hdr{background:#1B3A8C;color:#fff;padding:6px 20px 18px;border-radius:0 0 28px 0;margin-bottom:6px}.hdr .sub{color:#C9D5FF}.hdr .sub b{background:#E8452C;color:#fff;padding:1px 7px;border-radius:5px;font-size:11px}.status{background:#1B3A8C;color:#fff}
.av.a0{background:#E8452C;color:#fff;border-radius:50%}.av.a1{background:#F5B82E;color:#0F1B3D;border-radius:8px}.av.a2{background:#1F9D6B;color:#fff;border-radius:50% 50% 0 0}.av.a3{background:#1B3A8C;color:#fff;border-radius:50%}
.dot{background:#E8452C;border-radius:2px}.row{border-bottom:1px solid #E6EAF3}.tab.on{color:#1B3A8C}.tab.on svg{background:#DCE4FA;border-radius:10px;padding:2px;width:44px;box-sizing:content-box}
.dd.now{background:#F5B82E;color:#0F1B3D}.dd.now i{background:#0F1B3D}.ec{width:8px;border-radius:3px;background:#1B3A8C}.ev:nth-child(3n) .ec{background:#E8452C}.ev:nth-child(3n+1) .ec{background:#1F9D6B}.dh.t{color:#E8452C}
.actions span{background:#fff;box-shadow:0 1px 0 #D9DEEA}.actions span:first-child{background:#1B3A8C;color:#fff;border-color:#1B3A8C}
'''),
'B':dict(NAME='B · Timetable',BG='#E9E9EA',INK='#1D1D1F',GROUND='#FFFFFF',LINE='#1D1D1F',TABBG='#FFFFFF',MUTE='#6B6B70',TINT='#D6001C',BANNER='#F2F2F3',RAD='0',
 extra='''.hdr{border-bottom:3px solid #1D1D1F;padding-bottom:10px;margin:0 0 0}.ttl{font-size:30px;font-weight:700}.sub{font-variant-numeric:tabular-nums}
.av{border-radius:0;background:#1D1D1F;color:#fff;width:38px;height:38px;font-size:14px}.av.a0,.av.a1,.av.a2,.av.a3{background:#1D1D1F}.row{border-bottom:1px solid #D4D4D8}.row.unread .av{background:#D6001C}
.dot{display:none}.tm,.et b{font-variant-numeric:tabular-nums}.tab.on{color:#D6001C}.tabbar{border-top:3px solid #1D1D1F}
.dd.now{background:#D6001C;color:#fff}.dd.now small{color:#fff}.dd.now i{background:#fff}.ec{width:0;border-left:2px solid #1D1D1F}.ev{border-bottom:1px solid #D4D4D8;padding:12px 20px}.et b{font-size:17px}.dh{color:#1D1D1F;text-transform:none;font-size:14px;border-bottom:1px solid #1D1D1F;padding-left:20px}.dh.t{color:#D6001C}
.actions span{border-width:2px;border-color:#1D1D1F;color:#1D1D1F}.actions span:first-child{background:#D6001C;color:#fff;border-color:#D6001C}.banner{border-left:0;border:1px solid #1D1D1F}
'''),
'C':dict(NAME='C · Native standard',BG='#E5E5EA',INK='#000',GROUND='#FFFFFF',LINE='#D1D1D6',TABBG='#F9F9F9',MUTE='#8E8E93',TINT='#007AFF',BANNER='#F2F2F7',RAD='12px',
 extra='''.av{background:#C7C7CC;color:#fff}.av.a0{background:#A2845E}.av.a1{background:#5E5CE6}.av.a2{background:#34C759}.av.a3{background:#FF9500}.row{border-bottom:.5px solid #D1D1D6;margin-left:70px;padding-left:0;margin-left:0}
.dot{background:#007AFF;border-radius:50%;left:8px;right:auto;top:38px}.row{padding-left:26px}.row.unread .nm{font-weight:700}.ttl{font-weight:700}.dd.now{background:#007AFF;color:#fff;border-radius:50%}.dd.now small{color:#fff}.dd.now i{background:#fff}.ec{width:4px;border-radius:2px;background:#007AFF}
'''),}
def page(key):
    t=THEMES[key]; css=CSS_BASE
    for k in ['BG','INK','GROUND','LINE','TABBG','MUTE','TINT','BANNER','RAD']: css=css.replace('%'+k+'%',t[k])
    ph=lambda inner:f'<div class="phone">{inner}</div>'
    return f'<!doctype html><meta charset=utf-8><title>{t["NAME"]}</title><style>{css}{t["extra"]}</style><body>{ph(inbox(key))}{ph(message(key))}{ph(calendar(key))}'
for k in 'ABC': open(f'direction-{k}.html','w').write(page(k))
print('ok')
