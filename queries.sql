select count(patient_id) as total_patients 
from public.patient;

select 
    d.department_id,
    d.department_name,
    count(doc.doctor_id) as total_doctors
from public.department d
join public.doctor doc
on d.department_id = doc.department_id
group by d.department_id, d.department_name
having count(doc.doctor_id) > 1
order by d.department_id;

create or replace view public.vw_patient_appointment_details as
select
    a.appointment_id,
    a.appointment_date,
    a.appointment_start_time,
    a.appointment_end_time,
    a.appointment_status,
    p.patient_id,
    p.patient_name,
    doc.doctor_id,
    doc.doctor_name,
    d.department_name,
    h.hospital_name,
    mr.diagnosis
from public.appointment a
join public.patient p
on a.patient_id = p.patient_id
join public.doctor doc
on a.doctor_id = doc.doctor_id
join public.department d
on doc.department_id = d.department_id
join public.hospital h
on d.hospital_id = h.hospital_id
left join public.medical_record mr
on a.appointment_id = mr.appointment_id;

select *
from public.vw_patient_appointment_details
order by appointment_id;

select
    patient_id,
    patient_name,
    gender
from public.patient
where patient_id in (
    select patient_id
    from public.appointment
    where appointment_status = 'Completed'
)
order by patient_id;

SELECT CONCAT(DOCTOR_ID, ' : ', DOCTOR_NAME) AS DOCTOR_INFO
FROM DOCTOR;

SELECT LPAD(DOCTOR_ID, 10, '*') FROM DOCTOR;

--trigger to prevent double booking, and prevent overlapping
create or replace function public.prevent_double_booking()
returns trigger as $$
begin
	if exists(
	select 1
	from public.appointment
	where doctor_id = new.doctor_id
		and appointment_date = new.appointment_date
		and appointment_status <> 'Cancelled'
		and appointment_id <> new.appointment_id
		and new.appointment_start_time < appointment_end_time
		and new.appointment_end_time > appointment_start_time
	)then
		raise exception 'Doctors % already has an active appointment on % between % and %',
			new.doctor_id, new.appointment_date, new.appointment_start_time, new.appointment_end_time;
	end if;
	return new;
end
$$ LANGUAGE plpgsql;

drop trigger if exists trg_prevent_double_booking on public.appointment;

create trigger trg_prevent_double_booking
before insert or update on public.appointment
for each row
execute function public.prevent_double_booking();


--trigger make sure appointment is booked in the future
create or replace  function public.check_appointment_date()
returns trigger as $$
begin
	if(TG_OP = 'INSERT' or new.appointment_date <> old.appointment_date)
	and new.appointment_date < current_date then
		raise exception 'Please ensure that the date chosen is not in the past';
	end if;

	return new;
end;
$$ language plpgsql;

drop trigger if exists trg_check_appointment_date on public.appointment;

create trigger trg_check_appointment_date
before insert or update on public.appointment
for each row
execute function public.check_appointment_date();

--additional query for trigger#2
with old_snapshot as (
    select appointment_id, appointment_date as old_date
    from public.appointment
    where appointment_id = 'APT007'
)
update public.appointment a
set appointment_date = '2028-08-01'
from old_snapshot o
where a.appointment_id = o.appointment_id
returning a.appointment_id, o.old_date, a.appointment_date as new_date, a.appointment_status;

--strored proceudre to update appointment status
create or replace procedure update_appointment_status(
	p_appointment_id    VARCHAR(6),
	p_status            VARCHAR(20)
)
language plpgsql as $$
begin
	update appointment set appointment_status = p_status where appointment_id = p_appointment_id;
end;
$$;

select * from public.appointment;

--not in lecture 1(find duraton)
select 
	doc.doctor_name,
	d.department_name,
	a.appointment_id,
	a.appointment_date,
	a.appointment_start_time,
	a.appointment_end_time,
	extract(epoch from(a.appointment_end_time - a.appointment_start_time)) / 60
		as duration_minutes,
	a.appointment_status
from public.appointment a
join public.doctor doc
	on a.doctor_id = doc.doctor_id
join public.department d
	on doc.department_id = d.department_id
order by duration_minutes desc, doctor_name;

--not in lecture 2(find open timeslot)
CREATE OR REPLACE FUNCTION public.find_available_slots(p_date DATE, p_department_name varchar(100))
RETURNS TABLE (
    doctor_id        CHAR(6),
    doctor_name      VARCHAR(100),
    department_name  VARCHAR(100),
    available_start  TIME,
    available_end    TIME
) AS $$
BEGIN
    RETURN QUERY
    SELECT
        doc.doctor_id,
        doc.doctor_name,
        d.department_name,
        slot_start::time AS available_start,
        (slot_start + interval '30 minutes')::time AS available_end
    FROM public.doctor doc
    JOIN public.department d
        ON doc.department_id = d.department_id
    CROSS JOIN generate_series(
        (p_date + time '09:00')::timestamp,
        (p_date + time '16:30')::timestamp,
        interval '30 minutes'
    ) AS slot_start
    where d.department_name = p_department_name
    and not exists (
        SELECT 1
        FROM public.appointment a
        WHERE a.doctor_id = doc.doctor_id
          AND a.appointment_date = p_date
          AND a.appointment_status <> 'Cancelled'
          AND slot_start::time < a.appointment_end_time
          AND (slot_start + interval '30 minutes')::time > a.appointment_start_time
    )
    ORDER BY doc.doctor_name, available_start;
END;
$$ LANGUAGE plpgsql;