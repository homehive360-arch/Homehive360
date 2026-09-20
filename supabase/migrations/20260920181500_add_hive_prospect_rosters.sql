-- Prospective Hive rosters let operators construct a Hive from Directory candidates
-- without treating selection or invitation as active Hive membership.
create table if not exists public.hive_prospects (
 id uuid primary key default gen_random_uuid(),
 hive_id uuid not null references public.hives(id) on delete cascade,
 business_id uuid not null references public.businesses(id) on delete cascade,
 category text not null,
 -- category is the prospect's primary Hive seat, not every service the business offers.
 -- Exclusivity is scoped to this hive_id only; a business may join other Hives.

 roster_state text not null default 'prospective' check(roster_state in('prospective','invited','accepted','declined')),
 invited_at timestamptz,
 accepted_at timestamptz,
 declined_at timestamptz,
 created_at timestamptz not null default now(),
 updated_at timestamptz not null default now(),
 unique(hive_id,business_id)
);
create unique index if not exists hive_prospects_open_category_uq
 on public.hive_prospects(hive_id,lower(trim(category)))
 where roster_state in('prospective','invited','accepted');

-- The database, not only RPCs, owns category-seat exclusivity.

create index if not exists hive_prospects_hive_state_idx on public.hive_prospects(hive_id,roster_state,category);

alter table public.hive_prospects enable row level security;

create policy "active hive admins can view prospects" on public.hive_prospects
for select to authenticated using(exists(
 select 1 from public.hive_members hm
 join public.business_users bu on bu.business_id=hm.business_id
 where hm.hive_id=hive_prospects.hive_id
  and hm.status='active'
  and bu.user_id=(select auth.uid())
  and bu.role in('owner','admin')
));

create or replace function public.set_hive_prospect(
 p_hive_id uuid,
 p_business_id uuid,
 p_category text
) returns public.hive_prospects
language plpgsql security definer set search_path=''
as $function$
declare v public.hive_prospects;
begin
 if nullif(trim(p_category),'') is null then raise exception 'Category is required'; end if;
 if not exists(
  select 1 from public.hive_members hm
  join public.business_users bu on bu.business_id=hm.business_id
  where hm.hive_id=p_hive_id and hm.status='active'
   and bu.user_id=(select auth.uid()) and bu.role in('owner','admin')
 ) then raise exception 'Not authorized to build this Hive'; end if;
 if not exists(select 1 from public.businesses where id=p_business_id)
 then raise exception 'Business not found'; end if;
 if exists(
  select 1 from public.hive_member_seats hs
  where hs.hive_id=p_hive_id and hs.status='active'
   and lower(trim(hs.category))=lower(trim(p_category))
   and hs.business_id<>p_business_id
 ) then raise exception 'Category seat is already occupied by an active Hive member'; end if;
 if exists(select 1 from public.hive_members where hive_id=p_hive_id and business_id=p_business_id and status='active')
 then raise exception 'Business is already an active Hive member'; end if;

 insert into public.hive_prospects(hive_id,business_id,category)
 values(p_hive_id,p_business_id,trim(p_category))
 on conflict(hive_id,business_id) do update set
  category=excluded.category,updated_at=now()
 returning * into v;
 return v;
end
$function$;

revoke all on function public.set_hive_prospect(uuid,uuid,text) from public,anon;
grant execute on function public.set_hive_prospect(uuid,uuid,text) to authenticated;

create or replace function public.remove_hive_prospect(p_hive_id uuid,p_business_id uuid)
returns void language plpgsql security definer set search_path=''
as $function$
begin
 if not exists(
  select 1 from public.hive_members hm
  join public.business_users bu on bu.business_id=hm.business_id
  where hm.hive_id=p_hive_id and hm.status='active'
   and bu.user_id=(select auth.uid()) and bu.role in('owner','admin')
 ) then raise exception 'Not authorized to build this Hive'; end if;
 delete from public.hive_prospects where hive_id=p_hive_id and business_id=p_business_id and roster_state='prospective';
end
$function$;

revoke all on function public.remove_hive_prospect(uuid,uuid) from public,anon;
grant execute on function public.remove_hive_prospect(uuid,uuid) to authenticated;


create or replace function public.set_hive_prospect_state(
 p_hive_id uuid,
 p_business_id uuid,
 p_state text
) returns public.hive_prospects
language plpgsql security definer set search_path=''
as $function$
declare v public.hive_prospects;
begin
 if p_state not in('prospective','invited','accepted','declined')
 then raise exception 'Unsupported prospect state'; end if;
 if not exists(
  select 1 from public.hive_members hm
  join public.business_users bu on bu.business_id=hm.business_id
  where hm.hive_id=p_hive_id and hm.status='active'
   and bu.user_id=(select auth.uid()) and bu.role in('owner','admin')
 ) then raise exception 'Not authorized to manage this Hive'; end if;

 select * into v from public.hive_prospects
 where hive_id=p_hive_id and business_id=p_business_id for update;
 if v.id is null then raise exception 'Hive prospect not found'; end if;

 -- Acceptance records recruiting intent only. It does not create hive_members;
 -- activation remains a separate, explicit membership operation.
 update public.hive_prospects set
  roster_state=p_state,
  invited_at=case when p_state='invited' then coalesce(invited_at,now()) else invited_at end,
  accepted_at=case when p_state='accepted' then coalesce(accepted_at,now()) else accepted_at end,
  declined_at=case when p_state='declined' then coalesce(declined_at,now()) else declined_at end,
  updated_at=now()
 where id=v.id returning * into v;
 return v;
end
$function$;

revoke all on function public.set_hive_prospect_state(uuid,uuid,text) from public,anon;
grant execute on function public.set_hive_prospect_state(uuid,uuid,text) to authenticated;

create or replace function public.hive_build_readiness(p_hive_id uuid)
returns jsonb language sql security invoker set search_path='' stable
as $function$
 with authorized as(
  select exists(
   select 1 from public.hive_members hm
   join public.business_users bu on bu.business_id=hm.business_id
   where hm.hive_id=p_hive_id and hm.status='active'
    and bu.user_id=(select auth.uid()) and bu.role in('owner','admin')
  ) ok
 ),p as(
  select count(*)::bigint selected,
   count(*) filter(where roster_state='invited')::bigint invited,
   count(*) filter(where roster_state='accepted')::bigint accepted,
   count(*) filter(where roster_state='declined')::bigint declined
  from public.hive_prospects where hive_id=p_hive_id
 ),m as(
  select count(*)::bigint active_members
  from public.hive_members where hive_id=p_hive_id and status='active'
 )
 select case when (select ok from authorized)
  then jsonb_build_object(
   'selected',p.selected,'invited',p.invited,'accepted',p.accepted,
   'declined',p.declined,'active_members',m.active_members
  )
  else null end
 from p cross join m
$function$;

revoke all on function public.hive_build_readiness(uuid) from public,anon;
grant execute on function public.hive_build_readiness(uuid) to authenticated;



-- A business can belong to many Hives, but has one authoritative primary seat
-- inside each Hive. The partial unique index prevents two active competitors
-- from occupying the same category in the same Hive while allowing that same
-- category to be occupied in other Hives.
create table if not exists public.hive_member_seats (
 id uuid primary key default gen_random_uuid(),
 hive_id uuid not null references public.hives(id) on delete cascade,
 business_id uuid not null references public.businesses(id) on delete cascade,
 category text not null,
 status text not null default 'active' check(status in('active','inactive')),
 created_at timestamptz not null default now(),
 updated_at timestamptz not null default now(),
 unique(hive_id,business_id)
);
create unique index if not exists hive_member_seats_active_category_uq
 on public.hive_member_seats(hive_id,lower(trim(category))) where status='active';

create or replace function public.guard_hive_category_seat()
returns trigger language plpgsql security definer set search_path=''
as $function$
begin
 if new.status='active' and exists(
  select 1 from public.hive_prospects hp
  where hp.hive_id=new.hive_id
   and hp.roster_state in('prospective','invited','accepted')
   and lower(trim(hp.category))=lower(trim(new.category))
   and hp.business_id<>new.business_id
 ) then raise exception 'Category seat is reserved by an active prospect'; end if;
 return new;
end
$function$;

drop trigger if exists guard_hive_category_seat on public.hive_member_seats;
create trigger guard_hive_category_seat before insert or update of hive_id,business_id,category,status
on public.hive_member_seats for each row execute function public.guard_hive_category_seat();
alter table public.hive_member_seats enable row level security;
create policy "active hive members can view seats" on public.hive_member_seats
for select to authenticated using(exists(
 select 1 from public.hive_members hm join public.business_users bu on bu.business_id=hm.business_id
 where hm.hive_id=hive_member_seats.hive_id and hm.status='active' and bu.user_id=(select auth.uid())
));

create or replace function public.activate_hive_prospect(
 p_hive_id uuid,
 p_business_id uuid
) returns public.hive_members
language plpgsql security definer set search_path=''
as $function$
declare v_prospect public.hive_prospects;v_member public.hive_members;
begin
 if not exists(
  select 1 from public.hive_members hm
  join public.business_users bu on bu.business_id=hm.business_id
  where hm.hive_id=p_hive_id and hm.status='active'
   and bu.user_id=(select auth.uid()) and bu.role in('owner','admin')
 ) then raise exception 'Not authorized to activate members for this Hive'; end if;

 select * into v_prospect from public.hive_prospects
 where hive_id=p_hive_id and business_id=p_business_id for update;
 if v_prospect.id is null then raise exception 'Hive prospect not found'; end if;
 if v_prospect.roster_state<>'accepted' then raise exception 'Prospect must accept before membership activation'; end if;

 -- Category exclusivity belongs to the Hive seat, not to every service a
 -- business happens to offer. Existing active members must therefore have an
 -- authoritative seat assignment before prospect conversion can be enforced.
 if exists(
  select 1 from public.hive_member_seats hs
  where hs.hive_id=p_hive_id and hs.status='active'
   and lower(trim(hs.category))=lower(trim(v_prospect.category))
   and hs.business_id<>p_business_id
 ) then raise exception 'Category seat is already occupied by an active Hive member'; end if;

 insert into public.hive_members(hive_id,business_id,status)
 values(p_hive_id,p_business_id,'active')
 on conflict(hive_id,business_id) do update set status='active'
 returning * into v_member;

 insert into public.hive_member_seats(hive_id,business_id,category,status)
 values(p_hive_id,p_business_id,v_prospect.category,'active')
 on conflict(hive_id,business_id) do update set category=excluded.category,status='active',updated_at=now();

 delete from public.hive_prospects where id=v_prospect.id;
 return v_member;
end
$function$;

revoke all on function public.activate_hive_prospect(uuid,uuid) from public,anon;
grant execute on function public.activate_hive_prospect(uuid,uuid) to authenticated;


-- Market identity is deliberately non-unique: one market can contain many Hives.
alter table public.hives add column if not exists market_key text;
alter table public.hives add column if not exists market_sequence integer;
alter table public.hives add column if not exists market_label text;

create unique index if not exists hives_market_sequence_uq
 on public.hives(lower(trim(market_key)),market_sequence)
 where market_key is not null and market_sequence is not null;

create or replace function public.next_hive_market_sequence(p_market_key text)
returns integer language sql security invoker set search_path='' volatile
as $function$
 select coalesce(max(h.market_sequence),0)+1
 from public.hives h
 where lower(trim(h.market_key))=lower(trim(p_market_key)) and nullif(trim(p_market_key),'') is not null
$function$;

revoke all on function public.next_hive_market_sequence(text) from public,anon;
grant execute on function public.next_hive_market_sequence(text) to authenticated;

-- Example:
-- market_key = 'brunswick-ga'
-- market_sequence = 1, 2, 3...
-- market_label = 'Brunswick / Golden Isles'
-- No uniqueness constraint exists on market_key itself. Competition boundaries
-- remain the category seats inside each individual Hive.
