import random
import datetime

# define the number of rows to generate
num_rows = 300

# define the range of values for each column
job_id_range = (1, 1)
facility_id = (1, 10)
start_time_range = (datetime.datetime(2023, 4, 12, 16, 0, 1), datetime.datetime(2023, 4, 12, 16, 0, 4))
completion_time_range = (datetime.datetime(2023, 4, 12, 16, 0, 0), datetime.datetime(2023, 4, 12, 16, 0, 0))

# generate the rows
facility = 1
dict = {}
rows = []
null = ['NULL']
rows.append((1,1,1,start_time_range[0].timestamp(),start_time_range[0].timestamp(),1))
for i in range(1, num_rows):
    job_id = random.randint(job_id_range[0], job_id_range[1])
    dest_facility = random.randint(facility_id[0], facility_id[1])
    start_time = random.uniform(start_time_range[0].timestamp(), start_time_range[1].timestamp())
    start_time = datetime.datetime.fromtimestamp(start_time).strftime('%Y-%m-%d %H:%M:%S')
    completion_time = random.uniform(completion_time_range[0].timestamp(), completion_time_range[1].timestamp())
    completion_time = datetime.datetime.fromtimestamp(completion_time).strftime('%Y-%m-%d %H:%M:%S')
    if dest_facility == 11:
        rows.append((job_id, i + 1, 1, start_time, completion_time, null[0]))
        facility = None
        continue
    else:
        rows.append((job_id, i + 1, 1, start_time, completion_time, dest_facility))
        if facility is not None:
            if (str(facility) + ' to ' + str(dest_facility) not in dict):
                dict[str(facility) + ' to ' + str(dest_facility)] = 1
            else:
                dict[str(facility) + ' to '  + str(dest_facility)] += 1
        facility = dest_facility
        

# print the rows
for i, row in enumerate(rows):
    if i == num_rows - 1:
        print(row, ";")
    else:
        print(row, ",")
dict = sorted(dict.items(), key=lambda x: x[1], reverse=True)
#print the top 10 most common routes
for i in range(10):
    print("--", dict[i])


