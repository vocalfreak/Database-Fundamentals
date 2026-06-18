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
    a.appointment_time,
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
from public.vw_patient_appointment_details;

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

-- trigger
--create or replace  function check_appointment_date()
--return trigger as $$
--begin
--	if new.appointment_date < current_date then
--		RAISE exception
--		'Appointment date cannot be in the past';
--	end if;
--
--	return new;
--end;
--$$
--language plpgsql;
--
--
--end


--trigger to prevent double booking, and prevent overlapping(KIV)
create or replace function public.prevent_double_booking()
returns trigger as $$
begin
	if exists(
	select 1
	from public.appointment
	where doctor_id = new.doctor_id
		and appointment_date = new.appointment_date
		and appointment_time = new.appointment_time
		and appointment_status <> 'Cancelled'
		and appointment_id <> new.appointment_id
		--and new.appointment_start_time < appointment_end_time
		--and new_appointment_end_time > appointment_start_time
	)then
		raise exception 'Doctor % already has an active appointment on % at %',
			new.doctor_id, new.appointment_date, new.appointment_time;
	end if;
	return new;
end
$$ LANGUAGE plpgsql;

drop trigger if exists trg_prevent_double_booking on public.appointment;

create trigger trg_prevent_double_booking
before insert or update on public.appointment
for each row
execute function public.prevent_double_booking();




