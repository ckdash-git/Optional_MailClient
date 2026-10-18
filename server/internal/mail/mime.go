package mail

import (
	"bytes"
	"crypto/rand"
	"encoding/hex"
	"errors"
	"fmt"
	"io"
	"mime"
	"net/url"
	"regexp"
	"strings"
	"time"

	"github.com/emersion/go-message"
	_ "github.com/emersion/go-message/charset" // legacy charsets (iso-8859-*, windows-125x, ...)
	gomail "github.com/emersion/go-message/mail"
	"github.com/microcosm-cc/bluemonday"

	"github.com/ckdash-git/optional_mailclient/server/internal/model"
)

const maxBodyText = 2 << 20 // per text/html body part

// parsed is what the MIME walk extracts from a raw message.
type parsed struct {
	header      gomail.Header
	text, html  string
	attachments []Attachment
}

var errStop = errors.New("stop")

// parseMessage walks a raw RFC 5322 message. If want >= 0 and sink is set, the decoded
// body of attachment #want is streamed to sink(attachment) and the walk stops.
func parseMessage(r io.Reader, want int, sink func(Attachment) io.Writer) (*parsed, error) {
	mr, err := gomail.CreateReader(r)
	if err != nil && !message.IsUnknownCharset(err) {
		return nil, err
	}
	p := &parsed{header: mr.Header}
	idx := 0
	for {
		part, err := mr.NextPart()
		if err == io.EOF {
			return p, nil
		}
		if err != nil && !message.IsUnknownCharset(err) {
			return p, err
		}
		var att Attachment
		switch h := part.Header.(type) {
		case *gomail.InlineHeader:
			ct, params, _ := h.ContentType()
			_, dparams, _ := h.ContentDisposition()
			name := dparams["filename"]
			if name == "" && (ct == "text/plain" || ct == "text/html") {
				dst := map[string]*string{"text/plain": &p.text, "text/html": &p.html}[ct]
				if *dst == "" {
					b, _ := io.ReadAll(io.LimitReader(part.Body, maxBodyText))
					*dst = string(b)
					continue
				}
			}
			if name == "" {
				name = params["name"]
			}
			att = Attachment{Filename: name, ContentType: ct}
		case *gomail.AttachmentHeader:
			name, _ := h.Filename()
			ct, _, _ := h.ContentType()
			att = Attachment{Filename: name, ContentType: ct}
		}
		att.Index = idx
		if att.ContentType == "" {
			att.ContentType = "application/octet-stream"
		}
		if att.Filename == "" {
			att.Filename = fmt.Sprintf("attachment-%d", idx+1)
		}
		if idx == want && sink != nil {
			_, err := io.Copy(sink(att), part.Body)
			if err != nil {
				return p, err
			}
			return p, errStop
		}
		att.Size, _ = io.Copy(io.Discard, part.Body)
		p.attachments = append(p.attachments, att)
		idx++
	}
}

func addrs(h gomail.Header, key string) []model.Address {
	l, _ := h.AddressList(key)
	out := make([]model.Address, 0, len(l))
	for _, a := range l {
		out = append(out, model.Address{Name: a.Name, Email: a.Address})
	}
	return out
}

// fill copies the parsed body into m. Envelope fields (from, subject, date) come from
// the adapter's own summary.
func (p *parsed) fill(m *Message) {
	m.Cc = addrs(p.header, "Cc")
	m.ReplyTo = addrs(p.header, "Reply-To")
	if id, err := p.header.MessageID(); err == nil && id != "" {
		m.MessageID = "<" + id + ">"
	}
	if l, _ := p.header.MsgIDList("In-Reply-To"); len(l) > 0 {
		m.InReplyTo = "<" + l[0] + ">"
	}
	refs, _ := p.header.MsgIDList("References")
	m.References = make([]string, 0, len(refs))
	for _, r := range refs {
		m.References = append(m.References, "<"+r+">")
	}
	m.Text = p.text
	m.HTML, m.RemoteContentBlocked = Sanitize(p.html)
	m.Attachments = p.attachments
	if m.Attachments == nil {
		m.Attachments = []Attachment{}
	}
	m.HasAttachments = len(m.Attachments) > 0
}

// ---- HTML sanitising ----

var remoteRef = regexp.MustCompile(`(?i)(src|background|srcset)\s*=\s*["']?\s*(https?:|//|cid:)`)

var policy = func() *bluemonday.Policy {
	p := bluemonday.UGCPolicy()
	p.AllowDataURIImages()
	p.RequireNoReferrerOnLinks(true)
	p.AddTargetBlankToFullyQualifiedLinks(true)
	p.AllowElements("font", "center")
	p.AllowAttrs("color", "face", "size").OnElements("font")
	p.AllowAttrs("bgcolor", "align", "valign", "width", "height", "border", "cellpadding", "cellspacing").
		OnElements("table", "tr", "td", "th", "tbody", "thead", "img")
	// Remote and cid images are dropped: remote ones are tracking pixels more often than
	// not, and loading them would reveal the reader's IP to the sender.
	p.RewriteSrc(func(u *url.URL) {
		if u.Scheme != "data" {
			*u = url.URL{}
		}
	})
	return p
}()

// Sanitize returns safe HTML and whether remote content was removed.
func Sanitize(html string) (string, bool) {
	if html == "" {
		return "", false
	}
	return policy.Sanitize(html), remoteRef.MatchString(html)
}

// ---- building outgoing mail ----

type OutAttachment struct {
	Filename    string `json:"filename"`
	ContentType string `json:"content_type"`
	Data        []byte `json:"data_base64"` // encoding/json base64-decodes []byte
}

type Outgoing struct {
	To          []model.Address `json:"to"`
	Cc          []model.Address `json:"cc"`
	Bcc         []model.Address `json:"bcc"`
	Subject     string          `json:"subject"`
	Text        string          `json:"text"`
	HTML        string          `json:"html"`
	InReplyTo   string          `json:"in_reply_to"`
	References  []string        `json:"references"`
	Attachments []OutAttachment `json:"attachments"`
}

func toAddrs(l []model.Address) []*gomail.Address {
	out := make([]*gomail.Address, 0, len(l))
	for _, a := range l {
		out = append(out, &gomail.Address{Name: a.Name, Address: a.Email})
	}
	return out
}

func stripIDs(l []string) []string {
	out := make([]string, 0, len(l))
	for _, s := range l {
		if s = strings.Trim(strings.TrimSpace(s), "<>"); s != "" {
			out = append(out, s)
		}
	}
	return out
}

// Build renders o as an RFC 5322 message. Bcc recipients are not written to headers.
func Build(from model.Address, o Outgoing, now time.Time) (raw []byte, messageID string, err error) {
	var h gomail.Header
	h.SetDate(now)
	h.SetAddressList("From", toAddrs([]model.Address{from}))
	h.SetAddressList("To", toAddrs(o.To))
	if len(o.Cc) > 0 {
		h.SetAddressList("Cc", toAddrs(o.Cc))
	}
	h.SetSubject(o.Subject)
	var rnd [16]byte
	_, _ = rand.Read(rnd[:])
	_, dom, _ := strings.Cut(from.Email, "@")
	id := hex.EncodeToString(rnd[:]) + "@" + dom
	h.SetMessageID(id)
	if ids := stripIDs([]string{o.InReplyTo}); len(ids) > 0 {
		h.SetMsgIDList("In-Reply-To", ids)
	}
	if ids := stripIDs(o.References); len(ids) > 0 {
		h.SetMsgIDList("References", ids)
	}
	h.Set("MIME-Version", "1.0")

	var buf bytes.Buffer
	text := func(ct string) gomail.InlineHeader {
		var ih gomail.InlineHeader
		ih.SetContentType(ct, map[string]string{"charset": "utf-8"})
		ih.Set("Content-Transfer-Encoding", "quoted-printable")
		return ih
	}
	if len(o.Attachments) == 0 && o.HTML == "" {
		h.SetContentType("text/plain", map[string]string{"charset": "utf-8"})
		h.Set("Content-Transfer-Encoding", "quoted-printable")
		w, err := message.CreateWriter(&buf, h.Header)
		if err != nil {
			return nil, "", err
		}
		io.WriteString(w, o.Text)
		w.Close()
		return buf.Bytes(), "<" + id + ">", nil
	}
	mw, err := gomail.CreateWriter(&buf, h)
	if err != nil {
		return nil, "", err
	}
	iw, err := mw.CreateInline()
	if err != nil {
		return nil, "", err
	}
	parts := []struct{ ct, body string }{{"text/plain", o.Text}}
	if o.HTML != "" {
		safe, _ := Sanitize(o.HTML)
		parts = append(parts, struct{ ct, body string }{"text/html", safe})
	}
	for _, p := range parts {
		pw, err := iw.CreatePart(text(p.ct))
		if err != nil {
			return nil, "", err
		}
		io.WriteString(pw, p.body)
		pw.Close()
	}
	iw.Close()
	for _, a := range o.Attachments {
		var ah gomail.AttachmentHeader
		ct := a.ContentType
		if _, _, err := mime.ParseMediaType(ct); err != nil || ct == "" {
			ct = "application/octet-stream"
		}
		ah.SetContentType(ct, nil)
		ah.SetFilename(a.Filename)
		ah.Set("Content-Transfer-Encoding", "base64")
		aw, err := mw.CreateAttachment(ah)
		if err != nil {
			return nil, "", err
		}
		aw.Write(a.Data)
		aw.Close()
	}
	if err := mw.Close(); err != nil {
		return nil, "", err
	}
	return buf.Bytes(), "<" + id + ">", nil
}
