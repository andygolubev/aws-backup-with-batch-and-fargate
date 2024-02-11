FROM ubuntu:22.04
WORKDIR /tmp

# install tools
RUN apt update && apt -y upgrade && apt -y --no-install-suggests --no-install-recommends install wget unzip curl tree git jq gettext zip ca-certificates

# install aws cli v2
RUN curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip" && \
    unzip awscliv2.zip && \
    ./aws/install && \ 
    aws --version

# install latest postgre tools
RUN apt -y install lsb-release gnupg2 --no-install-suggests --no-install-recommends && \
    sh -c 'echo "deb http://apt.postgresql.org/pub/repos/apt $(lsb_release -cs)-pgdg main" > /etc/apt/sources.list.d/pgdg.list' && \
    wget --quiet -O - https://www.postgresql.org/media/keys/ACCC4CF8.asc | apt-key add - && \
    apt update && \
    apt -y install postgresql-client

# make working folders
RUN mkdir /backuper; mkdir /backup; mkdir /backup_db
WORKDIR /backuper

# declare variables for s3_backup_script.sh
ENV DO_KEY=NOT_DEFINED
ENV DO_SECRET=NOT_DEFINED
ENV DO_REGION_ENDPOINT=NOT_DEFINED
ENV AWS_BACKUP_DESTINATION_BUCKET=NOT_DEFINED

# declare variables for postgre_backup_script.sh
ENV DO_PG_HOST=NOT_DEFINED
ENV DO_PG_PORT=NOT_DEFINED
ENV DO_PG_USER=NOT_DEFINED
ENV DO_PG_PASSWORD=NOT_DEFINED
ENV DO_PG_DBNAME=NOT_DEFINED

# create a buckets backup script inside the docker image
RUN echo "BUCKETS_ALL=\$(AWS_ACCESS_KEY_ID=\$DO_KEY AWS_SECRET_ACCESS_KEY=\$DO_SECRET aws s3 ls --endpoint=\$DO_REGION_ENDPOINT  | awk '{print \$3}')" >> /backuper/s3_backup_script.sh
RUN echo '\
echo "This buckets will be processed: $BUCKETS_ALL" \n\
for BUCKET in $BUCKETS_ALL \n\
do \n\
  echo "Processing bucket -> $BUCKET" \n\
  mkdir -p /backup/$BUCKET/ \n\
  AWS_ACCESS_KEY_ID=$DO_KEY AWS_SECRET_ACCESS_KEY=$DO_SECRET aws s3 cp --quiet --recursive --endpoint=$DO_REGION_ENDPOINT s3://$BUCKET /backup/$BUCKET/ \n\
  ZIP_FILE_DATE_TIME=$(date +%Y-%m-%d--%H-%M) \n\
  zip --recurse-paths --quiet /backup/$ZIP_FILE_DATE_TIME-UTC-$BUCKET-bucket_backup.zip /backup/$BUCKET/ \n\
  aws s3 cp --storage-class GLACIER_IR /backup/$ZIP_FILE_DATE_TIME-UTC-$BUCKET-bucket_backup.zip  s3://$AWS_BACKUP_DESTINATION_BUCKET \n\
  echo "Successfully Processed -> $BUCKET" \n\
done \
echo "Bucket backup is COMPLITED" \
' >> /backuper/s3_backup_script.sh

# create a postgre backup script inside the docker image
RUN echo '\
echo "Making dump for PostgreSQL Database --> $DO_PG_DBNAME" \n\
mkdir -p /backup_db/$DO_PG_DBNAME/ \n\
PGPASSWORD=$DO_PG_PASSWORD pg_dump -U $DO_PG_USER -h $DO_PG_HOST -p $DO_PG_PORT -Fc $DO_PG_DBNAME > /backup_db/$DO_PG_DBNAME/$DO_PG_DBNAME.dump \n\
PGPASSWORD=$DO_PG_PASSWORD pg_dump -U $DO_PG_USER -h $DO_PG_HOST -p $DO_PG_PORT $DO_PG_DBNAME > /backup_db/$DO_PG_DBNAME/$DO_PG_DBNAME.sql \n\
ZIP_FILE_DATE_TIME=$(date +%Y-%m-%d--%H-%M) \n\
zip --recurse-paths --quiet /backup_db/$ZIP_FILE_DATE_TIME-UTC-$DO_PG_DBNAME-postgre_backup.zip /backup_db/$DO_PG_DBNAME/ \n\
aws s3 cp --storage-class GLACIER_IR /backup_db/$ZIP_FILE_DATE_TIME-UTC-$DO_PG_DBNAME-postgre_backup.zip  s3://$AWS_BACKUP_DESTINATION_BUCKET \n\
echo "Successfully Processed -> $DO_PG_DBNAME" \n\
echo "Postgre backup is COMPLITED" \
' >> /backuper/postgre_backup_script.sh

# make the script runnable
RUN chmod +x /backuper/s3_backup_script.sh
RUN chmod +x /backuper/postgre_backup_script.sh

ENTRYPOINT ["/bin/bash", "-c",  "/backuper/s3_backup_script.sh && /bin/bash -c /backuper/postgre_backup_script.sh"]ocker 