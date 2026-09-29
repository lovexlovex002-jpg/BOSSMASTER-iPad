# BOSSMASTER iPad

แอป iPad สำหรับค้นด้วยรหัสหรือ URL โดยให้ network request ออกผ่าน iPad โดยตรง

## ความสามารถ
- ค้นด้วยรหัส เช่น START-628
- วาง URL หน้าเว็บแล้วค้น
- อ่าน title, description และรูปจาก HTML/OG metadata
- จัดกลุ่มรูปเบื้องต้นเป็น Poster/Cover/Gallery
- บันทึกรูปที่เลือกลง Photos
- GitHub Actions สำหรับ build บน macOS

## Build
Workflow อยู่ที่ .github/workflows/ios-build.yml
การติดตั้งบน iPad จริงต้องใช้ Apple signing/provisioning ที่ถูกต้อง

เว็บบางแห่งอาจใช้ JavaScript, login หรือ anti-bot ทำให้ generic parser อ่านไม่ได้; จึงต้องเพิ่ม adapter รายเว็บเมื่อจำเป็น
