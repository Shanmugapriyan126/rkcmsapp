-- RK-CMS · run once in Supabase > SQL Editor (safe to re-run). Matches your existing tables; no table changes.
-- Roles: ADMIN = full access · VIEWER = read-only · any other role (e.g. USER) = can also record consumption.

create or replace function public.is_admin() returns boolean language sql security definer stable set search_path=public as
$$ select exists(select 1 from profiles where id=auth.uid() and upper(role)='ADMIN' and upper(status)='ACTIVE') $$;

alter table profiles enable row level security; alter table chemicals enable row level security;
alter table consumption_logs enable row level security; alter table stock_transactions enable row level security;

-- profiles: everyone signed in can read names (shown in "Recorded by"); only admin can change
drop policy if exists rk_prof_sel on profiles; create policy rk_prof_sel on profiles for select to authenticated using (true);
drop policy if exists rk_chem_sel on chemicals; create policy rk_chem_sel on chemicals for select to authenticated using (true);
drop policy if exists rk_chem_ins on chemicals; create policy rk_chem_ins on chemicals for insert to authenticated with check (is_admin());
drop policy if exists rk_chem_upd on chemicals; create policy rk_chem_upd on chemicals for update to authenticated using (is_admin()) with check (is_admin());
drop policy if exists rk_log_sel on consumption_logs; create policy rk_log_sel on consumption_logs for select to authenticated using (true);
drop policy if exists rk_tx_sel on stock_transactions; create policy rk_tx_sel on stock_transactions for select to authenticated using (true);
drop policy if exists rk_tx_ins on stock_transactions; create policy rk_tx_ins on stock_transactions for insert to authenticated with check (is_admin());

-- Consumption: locks the row, checks stock, deducts, writes the log AND the ledger entry
drop function if exists public.record_chemical_consumption(uuid,date,text,numeric,text,text,text,text);
create function public.record_chemical_consumption(p_chemical_id uuid,p_consumption_date date,p_department text,p_quantity numeric,p_unit text,p_used_by text,p_purpose text,p_remarks text)
returns void language plpgsql security definer set search_path=public as $$
declare s numeric; a boolean;
begin
  if not exists(select 1 from profiles where id=auth.uid() and upper(status)='ACTIVE' and upper(role)<>'VIEWER') then raise exception 'Your role cannot record consumption'; end if;
  if p_quantity<=0 then raise exception 'Quantity must be greater than 0'; end if;
  select coalesce(stock,0), active into s, a from chemicals where id=p_chemical_id for update;
  if not found then raise exception 'Chemical not found'; end if;
  if not a then raise exception 'Chemical is inactive'; end if;
  if p_quantity>s then raise exception 'Insufficient stock. Available: %', s; end if;
  update chemicals set stock=s-p_quantity, updated_at=now(), updated_by=auth.uid() where id=p_chemical_id;
  insert into consumption_logs(chemical_id,consumption_date,department,quantity,unit,used_by,purpose,remarks,recorded_by)
    values(p_chemical_id,coalesce(p_consumption_date,current_date),p_department,p_quantity,p_unit,p_used_by,p_purpose,p_remarks,auth.uid());
  insert into stock_transactions(chemical_id,transaction_type,quantity,previous_stock,new_stock,remarks,entered_by)
    values(p_chemical_id,'CONSUMPTION',p_quantity,s,s-p_quantity,coalesce(p_purpose,p_department),auth.uid());
end $$;

-- Receipt (adds) or Adjustment (sets stock to the physical count) – admin only
create or replace function public.record_stock_transaction(p_chemical_id uuid,p_type text,p_quantity numeric,p_remarks text default null)
returns void language plpgsql security definer set search_path=public as $$
declare s numeric; n numeric;
begin
  if not is_admin() then raise exception 'Admin access required'; end if;
  if p_type not in ('RECEIPT','ADJUSTMENT') then raise exception 'Invalid transaction type'; end if;
  if p_quantity<0 or (p_type='RECEIPT' and p_quantity=0) then raise exception 'Invalid quantity'; end if;
  select coalesce(stock,0) into s from chemicals where id=p_chemical_id for update;
  if not found then raise exception 'Chemical not found'; end if;
  n := case when p_type='RECEIPT' then s+p_quantity else p_quantity end;
  update chemicals set stock=n, updated_at=now(), updated_by=auth.uid() where id=p_chemical_id;
  insert into stock_transactions(chemical_id,transaction_type,quantity,previous_stock,new_stock,remarks,entered_by)
    values(p_chemical_id,p_type,n-s,s,n,p_remarks,auth.uid());
end $$;
grant execute on function public.record_chemical_consumption(uuid,date,text,numeric,text,text,text,text), public.record_stock_transaction(uuid,text,numeric,text) to authenticated;

-- SDS file storage (private bucket "sds"; opened with short-lived signed links)
insert into storage.buckets(id,name,public) values('sds','sds',false) on conflict (id) do nothing;
drop policy if exists rk_sds_sel on storage.objects; create policy rk_sds_sel on storage.objects for select to authenticated using (bucket_id='sds');
drop policy if exists rk_sds_ins on storage.objects; create policy rk_sds_ins on storage.objects for insert to authenticated with check (bucket_id='sds' and public.is_admin());
drop policy if exists rk_sds_del on storage.objects; create policy rk_sds_del on storage.objects for delete to authenticated using (bucket_id='sds' and public.is_admin());

-- Make yourself admin (after creating the user in Authentication > Users):
-- update profiles set role='ADMIN', status='ACTIVE' where id=(select id from auth.users where email='you@company.com');
