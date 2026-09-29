# BOSSMASTER iPad

แอป iPad สำหรับค้นด้วยรหัสหรือ URL โดยให้ network request ออกผ่าน iPad โดยตรง

## ความสามารถ
- ค้นด้วยรหัส เช่น START-628
- วาง URL หน้าเว็บแล้วค้น
- อ่าน title, description และรูปจาก HTML/OG metadata
- จัดกลุ่มรูปเบื้องต้นเป็น Poster/Cover/Gallery
- บันทึกรูปที่เลือกลง Photos
- GitHub Actions สำหรับ build บน macOS
- สร้าง `.ipa` แบบ Ad Hoc สำหรับ iPad จริงเมื่อใส่ Apple signing secrets

## การสร้าง IPA สำหรับ iPad จริง

Workflow อยู่ที่ `.github/workflows/ios-build.yml`

ต้องมี Apple Developer Program และต้องลงทะเบียน iPad ที่จะติดตั้งไว้ใน Apple Developer Account ก่อน จากนั้นสร้าง **Apple Distribution certificate** และ **Ad Hoc provisioning profile** สำหรับ Bundle ID:

`com.bossmaster.ipad`

Apple ระบุว่า Ad Hoc profile ใช้สำหรับติดตั้งแอปบนอุปกรณ์ที่ลงทะเบียนไว้ และ profile จะระบุ App ID, distribution certificate และรายชื่ออุปกรณ์ที่อนุญาตให้ติดตั้งได้

### GitHub Secrets ที่ต้องสร้าง

ไปที่ GitHub repository:
Settings → Secrets and variables → Actions → New repository secret

สร้าง 5 ตัวนี้:

1. `APPLE_TEAM_ID`
   - Team ID ของ Apple Developer Account

2. `IOS_CERTIFICATE_P12_BASE64`
   - ไฟล์ `.p12` ของ Apple Distribution certificate พร้อม private key
   - แปลงเป็น Base64 ก่อนนำไปใส่ secret

3. `IOS_CERTIFICATE_PASSWORD`
   - รหัสผ่านของไฟล์ `.p12`

4. `IOS_PROVISIONING_PROFILE_BASE64`
   - ไฟล์ Ad Hoc `.mobileprovision` ที่สร้างสำหรับ `com.bossmaster.ipad`
   - แปลงเป็น Base64 ก่อนนำไปใส่ secret

5. `KEYCHAIN_PASSWORD`
   - รหัสสุ่มที่ใช้ชั่วคราวสำหรับ keychain บน GitHub runner
   - ไม่ใช่รหัส Apple ID และไม่ใช่รหัส `.p12`

อย่าส่ง certificate, private key, `.p12`, provisioning profile หรือรหัสผ่านมาในแชต

### สร้าง Base64 บน Windows

เปิด PowerShell แล้วใช้:

```powershell
[Convert]::ToBase64String([IO.File]::ReadAllBytes("C:\path\BOSSMASTER.p12")) | Set-Clipboard
```

จากนั้นนำค่าที่อยู่ใน Clipboard ไปใส่ `IOS_CERTIFICATE_P12_BASE64`

สำหรับ provisioning profile:

```powershell
[Convert]::ToBase64String([IO.File]::ReadAllBytes("C:\path\BOSSMASTER.mobileprovision")) | Set-Clipboard
```

แล้วนำไปใส่ `IOS_PROVISIONING_PROFILE_BASE64`

### ชื่อ Provisioning Profile

Workflow นี้ใช้ชื่อ:

`BOSSMASTER iPad Ad Hoc`

ดังนั้นตอนสร้าง Ad Hoc provisioning profile ให้ตั้งชื่อ exact นี้ หรือแก้ชื่อทั้งใน workflow และ export options ให้ตรงกัน

### สร้าง IPA

หลังจากตั้ง Secrets ครบ:

1. เปิด GitHub → Actions
2. เลือก **BOSSMASTER iPad Build**
3. กด **Run workflow**
4. ตั้ง **สร้าง IPA สำหรับ iPad จริงด้วย Apple signing** เป็น `true`
5. รอ job `build_signed_ipa`
6. เมื่อสำเร็จ ให้เปิด Artifacts
7. ดาวน์โหลด `BOSSMASTER-iPad-IPA`
8. จะได้ไฟล์ `.ipa`

การ build แบบ push ปกติยังคงทำ unsigned Simulator build เพื่อเช็กว่า source compile ได้ โดยไม่แตะ signing secrets

## การติดตั้ง IPA

Ad Hoc IPA ติดตั้งได้เฉพาะ iPad ที่ถูกลงทะเบียนไว้ใน provisioning profile และต้องเปิด Developer Mode ตามขั้นตอนของ Apple สำหรับการติดตั้ง build จาก archive

หากต้องการแจกให้หลายคนหรืออัปเดตง่ายกว่า สามารถเปลี่ยน workflow ไปใช้ TestFlight/App Store Connect ได้ภายหลัง

## หมายเหตุเรื่องตัวค้นข้อมูล

Native iPad engine ทำ request จาก iPad โดยตรง ดังนั้น traffic ของตัวแอปจึงอยู่บน network ของ iPad และสามารถผ่าน VPN ของ iPad ได้

เว็บบางแห่งอาจใช้ JavaScript, login หรือ anti-bot ทำให้ generic parser อ่านไม่ได้; จึงต้องเพิ่ม adapter รายเว็บเมื่อจำเป็น
