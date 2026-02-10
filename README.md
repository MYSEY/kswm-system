# kswm_system_api

## PHP Envirornment: 8.3


## Missing how to setup project very quickly


### Super User Command
```
# Update email
php artisan user:super-update --email=admin@gmail.com

# Update name
php artisan user:super-update --name="Super User"

# Update password
php artisan user:super-update --password=88888888

# Update multiple fields
php artisan user:super-update --email=admin@gmail.com --name="Super User" --password=88888888
```


## Migrate to S3 storage
```sh
# Make scripts executable
chmod +x migrate-to-s3.sh
chmod +x test-env-loading.sh
```

```sh
# Test .env loading
./test-env-loading.sh

# Dry run migration using .env config
./migrate-to-s3.sh --dry-run

# run on server and write to file migrate_1.txt
nohup ./migrate-to-s3.sh > migrate_1.txt 2>&1

# Migrate specific folder using .env config
./migrate-to-s3.sh --path public --verbose

# Migrate Laravel storage folders using .env config
./migrate-to-s3.sh --laravel --verbose

# Full migration with exclusions using .env config
./migrate-to-s3.sh --exclude "*.log" --exclude "cache/*" --verbose
```


```sql
-- Make a backup first!
START TRANSACTION;

UPDATE pre_survey_files
SET full_path = REPLACE(full_path,
                        'https://www.wastiecollection.com',
                        'https://wbs-s3-live.sgp1.digitaloceanspaces.com');

-- Check affected rows; if OK:
COMMIT;
-- If not OK: ROLLBACK;
```
