# Hướng dẫn Timeline — cập nhật 13/10/2026

Áp dụng cho source/app chính cài cục bộ mới. Bản cài Release 1.0.1 đã phát hành trước đó chưa có toàn bộ thay đổi bên dưới.

## Ba cách tạo phụ đề

**Chép lời** tự nhận diện ngôn ngữ âm thanh, độc lập với ngôn ngữ chữ do OCR/kịch bản/dự án cũ cung cấp. Chữ phụ đề trên hình có thể là bản dịch nên không dùng để ép ngôn ngữ nhận diện âm thanh. Bản sửa này có trong source/app chính cục bộ sau preview1.0.1-preview.1.

| Nút trên thanh công cụ | Dùng khi | Cách hoạt động |
|---|---|---|
| **Chép lời** | Video/audio có lời nói | Chép lời từ âm thanh để tạo cue. Luồng nút Timeline hiện dùng Groq và cần key/mạng; đổi tên không đổi provider. |
| **Quét phụ đề** | Chữ phụ đề đã dính trong hình | OCR cục bộ đọc vùng chữ bạn chọn, ghép thành cue và SRT rời. Không nghe âm thanh, không cần key. |
| **Tạo sub từ văn bản** | Đã có kịch bản hoặc lời thoại | Nhập/dán văn bản, khớp thời gian theo lời nói trong video/audio. Nội dung văn bản là nguồn chuẩn. |

Nạp video/audio trước khi dùng các nút. **Tạo sub từ văn bản** mở cửa sổ nhập kịch bản: chọn ngôn ngữ hoặc Tự động, dán nội dung hoặc **Nhập TXT**, rồi bấm **Tạo sub**. Nếu đã có bản sub gốc trong cùng dự án, app ưu tiên chữ người dùng, thử dùng lại mốc cue khi khớp đủ và giữ nguyên thời gian; không chép lời lại/không cần model. Lệch nhiều thì giữ sub hiện có và báo để kiểm tra. Khi chưa có bản gốc, luồng khớp âm thanh vẫn dùng Whisper Offline nhúng và cần model riêng đã tải/import trong Cài đặt; người dùng không cần cài Python/Homebrew/FFmpeg. Xem [công cụ tích hợp](integrated-tools.md).

Tên nút **Tạo sub từ văn bản** thay cho **Văn bản gốc** trên thanh công cụ. Các nhãn chỉ bản transcript gốc/bản dịch vẫn giữ ý nghĩa cũ.

## Chọn vùng OCR

1. Nạp video có phụ đề dính trong hình.
2. Bấm **Quét phụ đề** cạnh nút âm thanh, hoặc dưới danh sách tệp bên trái.
3. Đưa thanh khung hình tới nơi có chữ, kéo chọn vùng sát phụ đề. **Vùng phía dưới** đặt lại vùng ban đầu.
4. Bấm **Quét phụ đề**; **Dừng quét** hoặc đóng cửa sổ sẽ hủy. Lỗi/hủy giữ phụ đề hiện có.
5. Kết quả thành cue/SRT rời để chỉnh, dịch, lồng tiếng hoặc xuất. OCR không xóa chữ khỏi video gốc.

App hiện dành cho Mac Apple Silicon, macOS15 trở lên. OCR dùng Vision cục bộ, không yêu cầu Apple Intelligence hay model Whisper. Các ngôn ngữ OCR có sẵn phụ thuộc macOS; app tập trung Việt/Anh/Nhật/Hàn/Trung theo danh sách hệ điều hành hỗ trợ. Chưa kiểm thực tế trên mọi phiên bản macOS/mẫu máy.

Chữ rõ và vùng chọn sạch là điều kiện thuận lợi. Chữ nhỏ/mờ, font cách điệu, nền phức tạp hoặc chữ hiện rất nhanh có thể cần sửa. Mặc định quét2 khung hình/giây; **Quét kỹ hơn** dùng4 khung hình/giây, không khôi phục được chữ đã mờ. Timing ước tính theo khung hình, chưa đối chiếu âm thanh. Kiểm tra clip mẫu đạt không phải cam kết độ chính xác cho mọi video. Xem [chi tiết OCR và giới hạn kiểm tra](subtitle-ocr.md).

## Đối chiếu OCR và âm thanh

Sau **Quét phụ đề** thành công, đóng cửa sổ quét sẽ hiện lời mời **Chép lời** để đối chiếu từ thiếu hoặc nhận diện sai. Chép lời xong không gợi ý quét OCR. **Để sau** bỏ qua; **Không nhắc lại** lưu lựa chọn. Lần chạy bổ trợ không hỏi tiếp và không tự chạy nhận diện hay dùng API.

Menu **Đối chiếu** trên thanh công cụ luôn cho mở lại khi đã có sub, kể cả tắt lời mời. OCR vẫn chọn vùng/quét cục bộ; âm thanh cho chọn Groq cloud (có dùng hạn mức khi bấm chạy) hoặc Whisper Offline đã tải.

Hai bản giữ riêng cho đến khi bấm **Áp dụng lựa chọn**. Chọn bản đúng theo từng nhóm thời gian; mặc định giữ hiện có. Có thể xem/nghe video, lọc khác biệt và xem ngôn ngữ của hai nguồn. Một nhóm có thể chứa nhiều cue vì hai nguồn ngắt câu khác nhau. Chọn bản bổ trợ dùng cả chữ và timing của nhóm đó, không nội suy thời gian mới. Chữ trên video có thể là bản dịch; app không tự kết luận nguồn nào đúng.

Áp dụng có **Hoàn tác**. Hủy/lỗi/đổi dự án hoặc sửa cue giữa chừng giữ bản đang chỉnh. Cue giữ nguyên lời/span còn dùng được audio; cue đổi chữ có thể cần lồng lại. [Chi tiết và kiểm tra](subtitle-comparison.md).

## Kiểm tra và sửa QC

- Giữ hai nút **1 dòng / 2 dòng**. Chọn **2 dòng** sẽ tìm điểm ngắt an toàn cả với cue ngắn; cue không chia được báo **Chưa đủ 2 dòng** trong QC. Cue hiện có giữ nguyên số lượng/ID/thời gian/khoảng nghỉ; không tự gộp để đủ dòng. Nhật giữ cách bố trí đã ổn. Chọn **1 dòng**: cue có2 dòng vẫn vượt giới hạn.
- Trong **QC**, mở menu của cue: **Xem cue**, **Sửa bố cục cue** hoặc **Sửa cue thủ công**.
- **Sửa các cue lệch số dòng** xử lý nhóm cue vượt giới hạn hiện tại. Có **Hoàn tác/Làm lại**; sửa chạy ở nền, không gọi API.
- Cue rỗng mở phần sửa chữ. Timing chồng được đưa tới Timeline để chỉnh thủ công; app không tự đoán chữ thiếu hoặc tự cắt lời.
- Cue quá dài có thể được tách, giữ chữ và khoảng thời gian gốc. Thời điểm chia theo trọng số chữ là ước tính, cần xem lại theo video.
- Cue giữ nguyên lời và thời gian có liên kết cache/tốc độ để giữ lồng tiếng khi đổi số thứ tự hoặc mở lại SRT. Cue bị đổi/tách có thể cần lồng tiếng lại. Nếu bố cục/cache không thể chuyển an toàn, cue được giữ để sửa thủ công.

QC tự động chỉ báo lỗi. Chỉ thao tác sửa do người dùng bấm mới đổi phụ đề.

## Vị trí toàn bộ phụ đề

Mở **Kiểu sub → Vị trí phụ đề**. Mục này hiện trên cả Thiết kế/Hiệu ứng:

- Kéo sang phải hoặc bấm mũi tên lên để nâng toàn bộ phụ đề.
- Kéo sang trái hoặc bấm mũi tên xuống để hạ.
- Nút đặt lại chỉ phục hồi vị trí mặc định.

Vị trí lưu trong style của dự án, không đổi chữ, timing hoặc ngắt dòng. Preview/video dùng chung cách đặt vị trí và giới hạn box chữ trong khung hình. Xem [kiểm tra vị trí](build-and-test.md#global-subtitle-position).

## Canh độ dài lồng tiếng

DUB mặc định đổi tốc độ phát để giữ đủ audio trong span SUB, không tạo giọng lại qua API. Kéo mép phải DUB để chỉnh độ dài riêng. Double-click mép về1×; bấm phải → **Khớp độ dài sub** để canh tự động lại. Tốc độ đã chỉnh thủ công được giữ khi đổi timing SUB. Cue quá nhanh/chậm được đánh dấu để xem lại; app không cắt chữ để giả vừa cue. SUB có timing chồng thì cần sửa timing trước.

Maziao mặc định **Đoạn liền mạch** để gom các cue gần nhau thành đoạn có ngữ cảnh. Một khối DUB phủ nhiều cue SUB; SUB giữ nguyên. **Lồng tiếng phần này** chỉ hiện khi chọn một hoặc nhiều phần phụ đề và tạo nguyên đoạn chứa phần đó, gồm các cue liền kề. DUB tự khớp tổng thời gian đoạn, có thể kéo độ dài riêng; mốc lời bên trong có thể lệch từng cue SUB nên cần nghe/xem lại. App không chạy thêm nhận diện audio. Cài đặt → Lồng tiếng → Maziao có **Từng cue** để chọn cách cũ. Đoạn tách bởi khoảng nghỉ dài có thể vẫn quá ngắn; app báo và không thêm chữ hoặc nối qua khoảng nghỉ để giả tăng ngữ cảnh.

**Lồng tiếng toàn bộ** vẫn hiện khi chưa chọn phần nào; khi đang tạo thì đổi thành **Dừng**. Nút phần chọn chỉ dành cho SUB, không hiện khi chọn DUB. Điều kiện key/giọng/busy vẫn quyết định có bấm được hay không. Tên nút thay **Lồng cue chọn / Lồng toàn bộ**; cơ chế tạo, thời gian, cache và API giữ nguyên.

Maziao vẫn tối đa2 nhóm API đồng thời; tải/chuyển mã trên máy tối đa2. Nếu tài khoản báo giới hạn đồng thời, chọn1 nhóm rồi bấm tạo lại để phục hồi receipt. Cache hai cách tạo được tách riêng, bản cũ không bị xóa. Tốc độ và chất giọng còn phụ thuộc hàng đợi/model/giọng bên Maziao. Xem [thực thi lồng tiếng và kiểm tra API](dubbing.md).

## Xuất kết quả

Ba nút riêng đã gom thành **Xuất** trên thanh công cụ:

- **Xuất SRT**: phụ đề rời có timecode.
- **Xuất TXT**: nội dung văn bản, không timecode.
- **Xuất XML**: phụ đề cho Final Cut Pro.

Xuất video phụ đề/lồng tiếng vẫn ở **Cài đặt xuất** trên titlebar. Các thao tác xuất dùng exporter hiện có.

## Đã kiểm tra và phần còn cần thử

Đợt sửa QC/vị trí/OCR đã qua90 kiểm tra core,24 đối chiếu XML, bộ native và các locale giao diện. Có clip mẫu kiểm vị trí một/hai dòng và fixture OCR5 ngôn ngữ. Việc đổi nhãn cuối cùng chỉ thay giao diện, được kiểm localization và build/startup app TEST; không chạy lại API. Chưa có corpus video người dùng lớn, kiểm mọi OS cũ hoặc chứng nhận từng thao tác menu bằng UI tự động. Quy trình ở [build và test](build-and-test.md).
