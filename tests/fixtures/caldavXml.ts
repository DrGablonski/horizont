// CalDAV-XML-Fixtures für extractAllIcs. Bewusst Roh-XML-Snippets wie von
// echten Servern (Radicale/Nextcloud/iCloud), inkl. Namespace-Präfixen und
// CDATA. ICS-Inhalte mit RFC-konformem CRLF.

function ics(lines: string[]): string {
	return lines.join('\r\n');
}

export const ICS_A = ics([
	'BEGIN:VCALENDAR',
	'VERSION:2.0',
	'PRODID:-//Test//EN',
	'BEGIN:VEVENT',
	'UID:evt-1@test',
	'SUMMARY:Erster Termin',
	'DTSTART:20250301T100000',
	'DTEND:20250301T110000',
	'END:VEVENT',
	'END:VCALENDAR'
]);

export const ICS_B = ics([
	'BEGIN:VCALENDAR',
	'VERSION:2.0',
	'BEGIN:VEVENT',
	'UID:evt-2@test',
	'SUMMARY:Zweiter Termin',
	'DTSTART:20250302T090000',
	'END:VEVENT',
	'END:VCALENDAR'
]);

/** Ein <response> mit nacktem <calendar-data> (Default-Namespace DAV:). */
export const MULTISTATUS_PLAIN = `<?xml version="1.0" encoding="utf-8"?>
<multistatus xmlns="DAV:">
  <response>
    <href>/cal/personal/evt-1.ics</href>
    <getetag>"abc123"</getetag>
    <calendar-data>${ICS_A}</calendar-data>
  </response>
</multistatus>`;

/** Namesierte Präfixe (C:/D:), wie von Nextcloud/iCloud gesendet. */
export const MULTISTATUS_NAMESPACED = `<?xml version="1.0" encoding="utf-8"?>
<D:multistatus xmlns:D="DAV:" xmlns:C="urn:ietf:params:xml:ns:caldav">
  <D:response>
    <D:href>http://dav.local/cal/priv/evt-2.ics</D:href>
    <D:propstat>
      <D:prop>
        <C:calendar-data>${ICS_B}</C:calendar-data>
      </D:prop>
    </D:propstat>
  </D:response>
</D:multistatus>`;

/** calendar-data mit Attributen (Content-Type). */
export const MULTISTATUS_WITH_ATTRS = `<multistatus xmlns="DAV:">
  <response>
    <calendar-data Content-Type="text/calendar; charset=utf-8">${ICS_A}</calendar-data>
  </response>
</multistatus>`;

/** ICS vollständig in CDATA verpackt. */
export const MULTISTATUS_CDATA = `<multistatus xmlns="DAV:">
  <response>
    <calendar-data><![CDATA[${ICS_A}]]></calendar-data>
  </response>
</multistatus>`;

/** CDATA direkt im <response> (ohne calendar-data-Wickel). */
export const MULTISTATUS_CDATA_DIRECT = `<multistatus xmlns="DAV:">
  <response><![CDATA[${ICS_B}]]></response>
</multistatus>`;

/** calendar-data ohne Wickel: ICS-Text beginnt direkt im Block. */
export const MULTISTATUS_DIRECT = `<multistatus xmlns="DAV:">
  <response>
    ${ICS_A}
  </response>
</multistatus>`;

/**
 * XML-Entities WERTEN: echte Server escapen Sonderzeichen im ICS-Inhalt
 * (&lt; &gt; &amp;), die Zeilenstruktur selbst bleibt literal.
 */
export const MULTISTATUS_ENTITIES = `<multistatus xmlns="DAV:">
  <response>
    <calendar-data>${ics([
			'BEGIN:VCALENDAR',
			'VERSION:2.0',
			'BEGIN:VEVENT',
			'UID:evt-3@test',
			'SUMMARY:Meeting &lt;Q2&gt; Planung',
			'DESCRIPTION:Escaped: &amp;lt; &amp; und &lt;b&gt;fett&lt;/b&gt;',
			'DTSTART:20250303T140000',
			'END:VEVENT',
			'END:VCALENDAR'
		])}</calendar-data>
  </response>
</multistatus>`;

/** Mehrere responses: zwei mit ICS, einer ohne (muss übersprungen werden). */
export const MULTISTATUS_MULTI = `<D:multistatus xmlns:D="DAV:">
  <D:response>
    <D:href>/a/evt-1.ics</D:href>
    <D:calendar-data>${ICS_A}</D:calendar-data>
  </D:response>
  <D:response>
    <D:href>/a/deleted.ics</D:href>
    <D:propstat>
      <D:status>HTTP/1.1 404 Not Found</D:status>
    </D:propstat>
  </D:response>
  <D:response>
    <D:href>/a/evt-2.ics</D:href>
    <D:calendar-data>${ICS_B}</D:calendar-data>
  </D:response>
</D:multistatus>`;

/** Nur responses ohne ICS-Anteil. */
export const MULTISTATUS_NO_ICS = `<multistatus xmlns="DAV:">
  <response>
    <href>/cal/</href>
    <getetag>"x"</getetag>
  </response>
  <response>
    <href>/cal/other.vcf</href>
  </response>
</multistatus>`;
