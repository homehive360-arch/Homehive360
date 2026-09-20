create or replace function public.record_public_attribution_event(p_event_key text, p_hive_id uuid, p_business_id uuid, p_customer_id uuid, p_lead_id uuid, p_event_type text, p_properties jsonb)
returns boolean
language plpgsql
security definer
set search_path to ''
as $function$
begin
 if p_event_key is null or btrim(p_event_key)='' or length(p_event_key)>500 then raise exception 'invalid_event_key'; end if;
 if p_hive_id is null or p_business_id is null then raise exception 'missing_attribution_target'; end if;
 if p_event_type not in ('hive_page.visited','member.clicked','offer.clicked') then raise exception 'invalid_public_event_type'; end if;
 if p_properties is null or jsonb_typeof(p_properties)<>'object' then raise exception 'invalid_event_properties'; end if;
 if not exists(select 1 from public.hives h where h.id=p_hive_id and h.status='active') then raise exception 'inactive_hive'; end if;
 if not exists(select 1 from public.businesses b where b.id=p_business_id and b.status='active') then raise exception 'inactive_business'; end if;
 if not exists(select 1 from public.hive_members hm where hm.hive_id=p_hive_id and hm.business_id=p_business_id and hm.status='active') then raise exception 'inactive_hive_member'; end if;
 insert into private.public_event_dedupe(event_key) values(p_event_key) on conflict do nothing;
 if not found then return false; end if;
 insert into public.events(hive_id,business_id,customer_id,lead_id,event_type,actor_type,properties)
 values(p_hive_id,p_business_id,p_customer_id,p_lead_id,p_event_type,'customer',p_properties);
 return true;
end $function$;
