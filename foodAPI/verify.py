import sqlite3, json

c = sqlite3.connect("gcfd_food.db")
c.row_factory = sqlite3.Row

def one(q):
    return c.execute(q).fetchone()[0]

print("locations:", one("select count(*) from locations"))
print("active:", one("select count(*) from locations where is_active=1"))
print("services:", one("select count(*) from services"))
print("schedules:", one("select count(*) from service_schedules"))
print("with_email:", one("select count(*) from locations where contact_email is not null and contact_email != ''"))
print("with_phone:", one("select count(*) from locations where phone is not null and phone != ''"))
print("with_website:", one("select count(*) from locations where website is not null and website != ''"))

print("\n--- sample location 755 ---")
r = dict(c.execute(
    "select location_id,name,address1,city,zip_code,phone,website,contact_name,contact_email,food_programs from locations where location_id=755"
).fetchone())
print(json.dumps(r, indent=2))

print("\n--- its hours ---")
for x in c.execute(
    "select s.service_name, sc.week_day, sc.start_time_desc, sc.end_time_desc "
    "from service_schedules sc left join services s on s.location_service_id=sc.location_service_id "
    "where sc.location_id=755 order by sc.day_of_week"
).fetchall():
    print(dict(x))

print("\n--- last sync run ---")
print(dict(c.execute("select * from sync_runs order by id desc limit 1").fetchone()))
c.close()
