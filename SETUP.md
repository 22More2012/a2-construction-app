# A2 Construction — Setup Guide
## AppSheet → HTML App (Supabase + GitHub + Vercel)

---

## Step 1 — Create Your Supabase Project

1. Go to [supabase.com](https://supabase.com) → **New Project**
2. Name it `a2-construction`, choose a region (Singapore is closest to PH)
3. Copy your **Project URL** and **anon public key** from: Settings → API

---

## Step 2 — Run the Database Schema

1. In Supabase dashboard → **SQL Editor** → New Query
2. Paste the contents of `schema.sql`
3. Click **Run** — all 10 tables will be created with sample data

---

## Step 3 — Configure the HTML App

Open `index.html` and find these lines near the top of the `<script>` section:

```js
const CONFIG = {
  supabaseUrl: 'https://YOUR_PROJECT.supabase.co',
  supabaseKey: 'YOUR_ANON_KEY',
  ...
};
```

Replace with your actual values from Step 1.

Alternatively, the app reads from `localStorage` — you can set these in the browser console:
```js
localStorage.setItem('sb_url', 'https://xxxx.supabase.co');
localStorage.setItem('sb_key', 'eyJ...');
```

---

## Step 4 — Deploy to GitHub + Vercel

### GitHub
```bash
# Create a new repo at github.com, then:
git init
git add index.html schema.sql SETUP.md
git commit -m "Initial A2 Construction app"
git remote add origin https://github.com/YOUR_USERNAME/a2-construction.git
git push -u origin main
```

### Vercel
1. Go to [vercel.com](https://vercel.com) → **Add New Project**
2. Import your GitHub repo
3. Framework: **Other** (static HTML)
4. Deploy — you'll get a URL like `https://a2-construction.vercel.app`

Every `git push` auto-deploys the latest version.

---

## Step 5 — Google Sheets Sync (Optional but Recommended)

The app queues changes locally and can push/pull from your original Google Sheet.
This requires a **Supabase Edge Function**.

### 5a. Create a Google Service Account

1. Go to [Google Cloud Console](https://console.cloud.google.com)
2. APIs & Services → **Enable**: Google Sheets API
3. Create → Service Account → Download JSON key
4. In your Google Sheet, click **Share** → add the service account email with **Editor** access

### 5b. Deploy the Edge Function

Create `supabase/functions/sheets-sync/index.ts`:

```typescript
import { serve } from 'https://deno.land/std@0.168.0/http/server.ts';

const SHEET_ID = '14kuNwYsNKVAOOVRpbBZjhjmugge3-vtJDiDfLncXKNA';

serve(async (req) => {
  const { action, queue } = await req.json();
  const serviceKey = Deno.env.get('GOOGLE_SERVICE_KEY');
  const creds = JSON.parse(serviceKey!);

  // Get Google access token via JWT
  const token = await getGoogleToken(creds);

  if (action === 'push' && queue?.length) {
    for (const item of queue) {
      await appendToSheet(token, SHEET_ID, item.table, item.data);
    }
    return new Response(JSON.stringify({ ok: true, pushed: queue.length }));
  }

  if (action === 'pull') {
    const data = await readSheet(token, SHEET_ID, 'ConsEmp');
    return new Response(JSON.stringify({ ok: true, data }));
  }

  return new Response('{"error":"unknown action"}', { status: 400 });
});

async function getGoogleToken(creds: any) {
  // JWT implementation for service account auth
  // Use https://deno.land/x/djwt for production
  const resp = await fetch('https://oauth2.googleapis.com/token', {
    method: 'POST',
    headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
    body: new URLSearchParams({
      grant_type: 'urn:ietf:params:oauth:grant-type:jwt-bearer',
      assertion: await createJWT(creds),
    }),
  });
  const { access_token } = await resp.json();
  return access_token;
}

async function appendToSheet(token: string, sheetId: string, sheet: string, data: any) {
  const values = [Object.values(data)];
  await fetch(
    `https://sheets.googleapis.com/v4/spreadsheets/${sheetId}/values/${sheet}:append?valueInputOption=USER_ENTERED`,
    {
      method: 'POST',
      headers: { Authorization: `Bearer ${token}`, 'Content-Type': 'application/json' },
      body: JSON.stringify({ values }),
    }
  );
}

async function readSheet(token: string, sheetId: string, sheet: string) {
  const resp = await fetch(
    `https://sheets.googleapis.com/v4/spreadsheets/${sheetId}/values/${sheet}`,
    { headers: { Authorization: `Bearer ${token}` } }
  );
  return resp.json();
}

// Minimal JWT creator — replace with djwt for production
async function createJWT(creds: any) {
  // See: https://developers.google.com/identity/protocols/oauth2/service-account
  return 'REPLACE_WITH_REAL_JWT_IMPLEMENTATION';
}
```

Deploy:
```bash
supabase functions deploy sheets-sync
supabase secrets set GOOGLE_SERVICE_KEY='{"type":"service_account",...}'
```

---

## App Features Summary

| Feature | Description |
|---------|-------------|
| **Dashboard** | Stats: present/absent today, CA count, OT pending, employee totals |
| **Employees** | Full CRUD with search, filter by status, gov't IDs (SSS/PhilHealth/Pag-IBIG) |
| **Attendance** | Daily attendance marking (Present/Absent/Half/OT/Holiday) with time in/out |
| **Payroll** | Auto-compute basic pay, OT pay, CA deductions by period and area |
| **Cash Advance** | Request, approve, track deductions |
| **Overtime** | File OT with auto-computed amount |
| **Leave** | Apply for leave with type and approval |
| **Vale/Voucher** | Vale transaction tracking |
| **Morning Meeting** | Daily meeting log with attendee count |
| **Google Sheets Sync** | Push/pull data from the original Google Sheet |
| **Offline support** | Changes saved locally, synced when reconnected |

---

## Sheet Mapping (AppSheet → Supabase)

| AppSheet Table | Supabase Table | Notes |
|---------------|----------------|-------|
| ConsEmp | `employees` | Main employee master |
| ConsPayroll | `employees` + `payroll` | Payroll view of employees |
| ConsAtt | `attendance` | Daily attendance records |
| CAform | `cash_advances` | Cash advance requests |
| OTform | `overtime_requests` | OT requests |
| LEAVEform | `leaves` | Leave applications |
| ConsVale | `vales` | Vale/voucher transactions |
| Payroll | `payroll` | Payroll computations |
| Location | `locations` | Work sites |
| Customer | `customers` | Projects/clients |
| Morning Meeting | `morning_meetings` | Meeting logs |

---

## Support

- Supabase docs: https://supabase.com/docs
- Vercel docs: https://vercel.com/docs
- Google Sheets API: https://developers.google.com/sheets/api
