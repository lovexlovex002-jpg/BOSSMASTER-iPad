import SwiftUI

struct ContentView: View {
    @StateObject private var model = SearchModel()
    var body: some View {
        NavigationSplitView {
            VStack(spacing: 12) {
                Text("BOSSMASTER").font(.largeTitle.bold())
                Picker("โหมด", selection: $model.mode) {
                    Text("รหัส").tag(SearchMode.code)
                    Text("ลิงก์").tag(SearchMode.url)
                }.pickerStyle(.segmented)
                HStack {
                    TextField(model.mode == .code ? "เช่น START-628" : "วาง URL ของหน้าเว็บ", text: $model.query)
                        .textFieldStyle(.roundedBorder)
                        .textInputAutocapitalization(.never).autocorrectionDisabled()
                    Button("ค้นหา") { Task { await model.search() } }
                        .buttonStyle(.borderedProminent).disabled(model.isLoading)
                }
                if model.isLoading { ProgressView("กำลังค้นหา…") }
                if let error = model.error { Text(error).foregroundStyle(.red).font(.footnote) }
                List(model.records) { record in
                    Button { model.selected = record } label: {
                        VStack(alignment: .leading) {
                            Text(record.code).bold()
                            Text(record.title.isEmpty ? "ไม่พบชื่อเรื่อง" : record.title).lineLimit(2)
                            Text(record.source).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
            }.padding().navigationTitle("ค้นหา")
            TextField("ต้นทางค้น (ห้ามใส่รหัสผ่าน)", text: $model.sourceBase)
                .textFieldStyle(.roundedBorder)
                .font(.footnote)
                .padding([.horizontal, .bottom])
        } detail: {
            if let record = model.selected { DetailView(record: record, model: model) }
            else { ContentUnavailableView("ค้นหารหัสหรือวางลิงก์", systemImage: "magnifyingglass") }
        }
    }
}
struct DetailView: View {
    let record: SearchRecord
    @ObservedObject var model: SearchModel
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Text(record.code).font(.title.bold())
                Text(record.title).font(.title2)
                row("Actor", record.actor); row("Studio", record.studio); row("Release", record.releaseDate); row("Runtime", record.runtime); row("Source", record.source)
                if let page = record.pageURL { Link("เปิดหน้าต้นทาง", destination: page) }
                if !record.images.isEmpty {
                    Text("Poster / Cover / Gallery").font(.headline)
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 160))], spacing: 12) {
                        ForEach(record.images) { item in
                            VStack(alignment: .leading, spacing: 6) {
                                AsyncImage(url: item.url) { phase in
                                    switch phase {
                                    case .success(let image): image.resizable().scaledToFit()
                                    case .failure: Image(systemName: "photo.badge.exclamationmark").font(.largeTitle).frame(maxWidth: .infinity, minHeight: 140)
                                    default: ProgressView().frame(maxWidth: .infinity, minHeight: 140)
                                    }
                                }.clipShape(RoundedRectangle(cornerRadius: 10))
                                HStack { Text(item.role.rawValue).font(.caption.bold()); Spacer(); Button("บันทึก") { Task { await model.saveImage(item) } }.font(.caption) }
                            }
                        }
                    }
                }
                if let msg = model.saveMessage { Text(msg).font(.footnote).foregroundStyle(.secondary) }
                if !record.plot.isEmpty { Text("Plot").font(.headline); Text(record.plot) }
            }.padding()
        }.navigationTitle(record.code)
    }
    @ViewBuilder private func row(_ label: String, _ value: String) -> some View {
        if !value.isEmpty { VStack(alignment: .leading, spacing: 2) { Text(label).font(.caption).foregroundStyle(.secondary); Text(value) } }
    }
}
