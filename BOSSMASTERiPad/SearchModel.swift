import Foundation
import SwiftUI
import Photos
import UIKit

enum SearchMode: Hashable { case code, url }
enum ImageRole: String, Hashable { case poster = "Poster", cover = "Cover", gallery = "Gallery" }
struct ImageItem: Identifiable, Hashable { let id = UUID(); let url: URL; let role: ImageRole }
struct SearchRecord: Identifiable, Hashable {
    let id = UUID(); var code: String; var title=""; var actor=""; var studio=""; var releaseDate=""; var runtime=""; var plot=""; var source: String; var pageURL: URL?; var images:[ImageItem]=[]
}
@MainActor final class SearchModel: ObservableObject {
    @Published var query=""; @Published var mode: SearchMode = .code; @Published var records:[SearchRecord]=[]; @Published var selected:SearchRecord?; @Published var isLoading=false; @Published var error:String?; @Published var saveMessage:String?
    private let engine=NativeFetchEngine()
    func search() async {
        let value=query.trimmingCharacters(in:.whitespacesAndNewlines); guard !value.isEmpty else{return}
        isLoading=true; error=nil; saveMessage=nil; defer{isLoading=false}
        do { records = try await (mode == .code ? engine.search(code:value) : engine.search(urlString:value)); selected=records.first; if records.isEmpty {error="ไม่พบข้อมูล หรือเว็บไม่อนุญาตให้แอปอ่านหน้านี้"} }
        catch { error=error.localizedDescription }
    }
    func saveImage(_ item:ImageItem) async {
        do {
            let status=await PHPhotoLibrary.requestAuthorization(for:.addOnly)
            guard status == .authorized || status == .limited else { throw SaveError.photoPermission }
            let (data,response)=try await URLSession.shared.data(from:item.url)
            guard let http=response as? HTTPURLResponse,(200...399).contains(http.statusCode),let image=UIImage(data:data) else {throw SaveError.download}
            try await PHPhotoLibrary.shared().performChanges { PHAssetChangeRequest.creationRequestForAsset(from:image) }
            saveMessage="บันทึก \(item.role.rawValue) แล้ว"
        } catch { saveMessage="บันทึกไม่สำเร็จ: \(error.localizedDescription)" }
    }
}
enum SaveError:LocalizedError { case photoPermission,download; var errorDescription:String? { switch self {case .photoPermission:return "กรุณาอนุญาตให้ BOSSMASTER เพิ่มรูปใน Photos"; case .download:return "ดาวน์โหลดรูปจาก URL ไม่สำเร็จ"} } }
