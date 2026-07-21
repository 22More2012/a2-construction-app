-- ═══════════════════════════════════════════════════════════════
-- A2 Construction Attendance & Payroll — Supabase SQL Schema
-- Run this in your Supabase project: SQL Editor → New Query → Run
-- ═══════════════════════════════════════════════════════════════

-- ── Enable UUID extension ──────────────────────────────────────
create extension if not exists "pgcrypto";

-- ══════════════════════════════════════════════════════════════
-- 1. LOCATIONS (master list of work sites)
-- ══════════════════════════════════════════════════════════════
create table if not exists locations (
  id           text primary key default gen_random_uuid()::text,
  name         text not null,
  address      text,
  is_active    boolean default true,
  created_at   timestamptz default now(),
  updated_at   timestamptz default now()
);

insert into locations (name, address) values
  ('Laguna', 'Laguna Province'),
  ('Manila', 'Metro Manila'),
  ('Cavite', 'Cavite Province')
on conflict do nothing;

-- ══════════════════════════════════════════════════════════════
-- 2. CUSTOMERS / PROJECTS
-- ══════════════════════════════════════════════════════════════
create table if not exists customers (
  id             text primary key default gen_random_uuid()::text,
  name           text not null,
  contact_person text,
  phone          text,
  location       text,
  notes          text,
  is_active      boolean default true,
  created_at     timestamptz default now(),
  updated_at     timestamptz default now()
);

-- ══════════════════════════════════════════════════════════════
-- 3. EMPLOYEES  (ConsEmp / ConsPayroll)
-- ══════════════════════════════════════════════════════════════
create table if not exists employees (
  id                  text primary key default gen_random_uuid()::text,
  key_id              text unique,                -- e.g. "C001" (AppSheet Key ID)
  nickname            text,                       -- Nickname/Alias
  first_name          text not null,
  last_name           text not null,
  full_name           text generated always as (first_name || ' ' || last_name) stored,
  address             text,
  contact_number      text,
  pay_per_day         numeric(10,2) default 0,    -- Pay per day in PHP
  current_pay         numeric(10,2),              -- Computed current pay after increases
  position            text,                       -- Mason, Carpenter, Laborer, etc.
  location            text,                       -- Legacy location text
  area                text,                       -- Area / site
  location_id         text references locations(id),
  employee_status     text default 'Regular',     -- Regular, Project-based, Casual, Probationary
  status              text default 'Active',      -- Active, Resigned, On Leave, Terminated
  birthday            date,
  date_hired          date,
  date_resigned       date,
  referral_by         text,                       -- Referred by
  photo_url           text,
  -- Government IDs
  sss_no              text,
  philhealth_no       text,
  pagibig_no          text,
  -- Pay Increases (up to 3)
  increase_1_pay      boolean default false,
  increase_1_amount   numeric(10,2),
  increase_1_date     date,
  increase_2_pay      boolean default false,
  increase_2_amount   numeric(10,2),
  increase_2_date     date,
  increase_3_pay      boolean default false,
  increase_3_amount   numeric(10,2),
  increase_3_date     date,
  -- Audit
  added_by            text,
  updated_by          text,
  created_at          timestamptz default now(),
  updated_at          timestamptz default now()
);

-- ══════════════════════════════════════════════════════════════
-- 4. ATTENDANCE  (ConsAtt)
-- ══════════════════════════════════════════════════════════════
create table if not exists attendance (
  id           text primary key default gen_random_uuid()::text,
  employee_id  text not null references employees(id) on delete cascade,
  att_date     date not null,
  status       text not null default 'present',
  -- Values: present | absent | half | ot | holiday
  time_in      time,
  time_out     time,
  ot_hours     numeric(4,2) default 0,
  notes        text,
  location_id  text references locations(id),
  area         text,
  marked_by    text,
  created_at   timestamptz default now(),
  updated_at   timestamptz default now(),
  unique(employee_id, att_date)
);

create index if not exists idx_attendance_date on attendance(att_date);
create index if not exists idx_attendance_emp  on attendance(employee_id);

-- ══════════════════════════════════════════════════════════════
-- 5. CASH ADVANCES  (CAform)
-- ══════════════════════════════════════════════════════════════
create table if not exists cash_advances (
  id           text primary key default gen_random_uuid()::text,
  employee_id  text not null references employees(id) on delete cascade,
  request_date date default current_date,
  amount       numeric(10,2) not null default 0,
  purpose      text,
  status       text default 'Pending',
  -- Values: Pending | Approved | Released | Deducted | Cancelled
  approved_by  text,
  release_date date,
  payroll_id   text,                    -- link to payroll deduction
  notes        text,
  created_by   text,
  created_at   timestamptz default now(),
  updated_at   timestamptz default now()
);

create index if not exists idx_ca_employee on cash_advances(employee_id);
create index if not exists idx_ca_date     on cash_advances(request_date);

-- ══════════════════════════════════════════════════════════════
-- 6. OVERTIME REQUESTS  (OTform)
-- ══════════════════════════════════════════════════════════════
create table if not exists overtime_requests (
  id           text primary key default gen_random_uuid()::text,
  employee_id  text not null references employees(id) on delete cascade,
  ot_date      date not null,
  ot_hours     numeric(4,2) not null default 0,
  ot_rate      numeric(4,2) default 1.25,     -- multiplier (1.25 = 125%)
  ot_amount    numeric(10,2),                  -- computed
  reason       text,
  status       text default 'Pending',
  -- Values: Pending | Approved | Paid | Cancelled
  approved_by  text,
  created_by   text,
  created_at   timestamptz default now(),
  updated_at   timestamptz default now()
);

-- Auto-compute ot_amount
create or replace function compute_ot_amount()
returns trigger language plpgsql as $$
declare emp_pay numeric;
begin
  select pay_per_day into emp_pay from employees where id = new.employee_id;
  new.ot_amount := coalesce(new.ot_hours, 0) * coalesce(new.ot_rate, 1.25) * coalesce(emp_pay, 0) / 8;
  return new;
end;
$$;
create trigger trg_ot_amount before insert or update on overtime_requests
  for each row execute function compute_ot_amount();

-- ══════════════════════════════════════════════════════════════
-- 7. LEAVE APPLICATIONS  (LEAVEform)
-- ══════════════════════════════════════════════════════════════
create table if not exists leaves (
  id           text primary key default gen_random_uuid()::text,
  employee_id  text not null references employees(id) on delete cascade,
  leave_from   date not null,
  leave_to     date not null,
  leave_days   numeric(4,1),             -- computed or manual
  leave_type   text default 'Vacation Leave',
  -- Values: Sick Leave | Vacation Leave | Emergency | AWOL | Personal | Others
  reason       text,
  status       text default 'Pending',
  -- Values: Pending | Approved | Denied | Cancelled
  approved_by  text,
  created_by   text,
  created_at   timestamptz default now(),
  updated_at   timestamptz default now()
);

-- ══════════════════════════════════════════════════════════════
-- 8. VALE / VOUCHERS  (ConsVale)
-- ══════════════════════════════════════════════════════════════
create table if not exists vales (
  id           text primary key default gen_random_uuid()::text,
  employee_id  text not null references employees(id) on delete cascade,
  vale_date    date default current_date,
  amount       numeric(10,2) not null default 0,
  purpose      text,                    -- Particulars / Purpose
  approved_by  text,
  is_deducted  boolean default false,
  payroll_id   text,
  notes        text,
  created_by   text,
  created_at   timestamptz default now(),
  updated_at   timestamptz default now()
);

-- ══════════════════════════════════════════════════════════════
-- 9. PAYROLL  (Payroll / PayrollNo)
-- ══════════════════════════════════════════════════════════════
create table if not exists payroll (
  id              text primary key default gen_random_uuid()::text,
  payroll_no      text unique,          -- e.g. "PAY-2025-001"
  period_from     date not null,
  period_to       date not null,
  employee_id     text not null references employees(id),
  area            text,
  days_worked     numeric(4,1) default 0,
  basic_pay       numeric(10,2) default 0,
  ot_pay          numeric(10,2) default 0,
  ca_deduction    numeric(10,2) default 0,
  vale_deduction  numeric(10,2) default 0,
  sss_deduction   numeric(10,2) default 0,
  philhealth_deduction numeric(10,2) default 0,
  pagibig_deduction    numeric(10,2) default 0,
  other_deduction numeric(10,2) default 0,
  net_pay         numeric(10,2) default 0,
  status          text default 'Draft',  -- Draft | Finalized | Paid
  remarks         text,
  prepared_by     text,
  created_at      timestamptz default now(),
  updated_at      timestamptz default now()
);

create index if not exists idx_payroll_period on payroll(period_from, period_to);
create index if not exists idx_payroll_emp    on payroll(employee_id);

-- ══════════════════════════════════════════════════════════════
-- 10. MORNING MEETINGS  (Morning Meeting)
-- ══════════════════════════════════════════════════════════════
create table if not exists morning_meetings (
  id              text primary key default gen_random_uuid()::text,
  meet_date       date not null default current_date,
  location_id     text references locations(id),
  location_name   text,
  topic           text,
  attendees_count integer default 0,
  notes           text,
  facilitator     text,
  created_by      text,
  created_at      timestamptz default now()
);

-- ══════════════════════════════════════════════════════════════
-- 11. ROW-LEVEL SECURITY (enable for production)
-- ══════════════════════════════════════════════════════════════
-- Uncomment the lines below after setting up auth:
-- alter table employees        enable row level security;
-- alter table attendance        enable row level security;
-- alter table cash_advances    enable row level security;
-- alter table overtime_requests enable row level security;
-- alter table leaves           enable row level security;
-- alter table vales            enable row level security;
-- alter table payroll          enable row level security;
-- alter table morning_meetings enable row level security;
-- alter table locations        enable row level security;
-- alter table customers        enable row level security;

-- ══════════════════════════════════════════════════════════════
-- 12. SAMPLE DATA (optional — comment out for production)
-- ══════════════════════════════════════════════════════════════
insert into employees (key_id, first_name, last_name, nickname, position, area, pay_per_day, status, employee_status)
values
  ('C001','Danny','Abaño','Danny A','Mason','Laguna',600,'Resigned','Regular'),
  ('C002','Noli','Advincula','Noli','Landscaper','Laguna',500,'Active','Regular'),
  ('C003','Jose','Santos','Jojo','Carpenter','Laguna',650,'Active','Project-based'),
  ('C004','Maria','Cruz','Marie','Foreman','Laguna',900,'Active','Regular')
on conflict (key_id) do nothing;
