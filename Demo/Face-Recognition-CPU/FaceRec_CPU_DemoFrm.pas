unit FaceRec_CPU_DemoFrm;

interface

uses
  System.SysUtils, System.Types, System.UITypes, System.Classes, System.Variants,
  FMX.Types, FMX.Controls, FMX.Forms, FMX.Graphics, FMX.Dialogs, FMX.Controls.Presentation,
  FMX.StdCtrls, FMX.Objects, FMX.ScrollBox, FMX.Memo,

  System.IOUtils,

  CoreClasses,
  Learn, LearnTypes,
  zAI, zAI_Common,
  zDrawEngineInterface_SlowFMX, zDrawEngine, Geometry2DUnit, MemoryRaster,
  MemoryStream64, PascalStrings, UnicodeMixedLib, DoStatusIO, FMX.Layouts, FMX.ExtCtrls;

type
  TFaceRecForm = class(TForm)
    FaceRecButton: TButton;
    Memo1: TMemo;
    Timer1: TTimer;
    ResetButton: TButton;
    Image1: TImageViewer;
    procedure ResetButtonClick(Sender: TObject);
    procedure FaceRecButtonClick(Sender: TObject);
    procedure FormCreate(Sender: TObject);
    procedure Image1Click(Sender: TObject);
    procedure Timer1Timer(Sender: TObject);
  private
    procedure DoStatusMethod(AText: SystemString; const ID: Integer);
  public
    imgL: TAI_ImageList;
    AI: TAI;
    face_tile: TMemoryRaster;
    L_Engine: TLearn;
  end;

var
  FaceRecForm: TFaceRecForm;

implementation

{$R *.fmx}


procedure TFaceRecForm.ResetButtonClick(Sender: TObject);
var
  fn: U_String;

  procedure d(filename: U_String);
  begin
    DoStatus('ɾ���ļ� %s', [filename.Text]);
    umlDeleteFile(filename);
  end;

begin
  fn := umlCombineFileName(TPath.GetLibraryPath, 'lady_face' + zAI.C_Metric_ResNet_Ext);
  d(fn);
  d(fn + '.sync');
  d(fn + '.sync_');
  d(umlchangeFileExt(fn, '.learn'));
  MemoryBitmapToBitmap(face_tile, Image1.Bitmap);
end;

procedure TFaceRecForm.FaceRecButtonClick(Sender: TObject);
begin
  TComputeThread.RunP(nil, nil, procedure(Sender: TComputeThread)
    var
      fn, L_fn: U_String;
      param: PMetric_ResNet_Train_Parameter;
      training_successed: Boolean;
      mdnn_hnd: TMDNN_Handle;
      face_hnd: TFACE_Handle;
      tk: TTimeTick;
      new_face_tile: TMemoryRaster;
      i: Integer;
      d: TDrawEngine;
      face_raster: TMemoryRaster;
      face_vec: TLVec;
      face_token: SystemString;
      face_rect: TRectV2;
    begin
      TThread.Synchronize(Sender, procedure
        begin
          FaceRecButton.Enabled := False;
          ResetButton.Enabled := False;
        end);
      try
        DoStatus('���������������:%s', ['lady_face' + zAI.C_Metric_ResNet_Ext]);
        fn := umlCombineFileName(TPath.GetLibraryPath, 'lady_face' + zAI.C_Metric_ResNet_Ext);
        if not umlFileExists(fn) then
          begin
            // ����������api������ѵ���沿��������������
            // ͬ����ѵ��Ҳ����ʹ�� TTrainingTask ��ʽ
            DoStatus('��ʼѵ���������������:%s', ['lady_face' + zAI.C_Metric_ResNet_Ext]);
            param := TAI.Init_Metric_ResNet_Parameter(fn + '.sync', fn);

            // �����ѧϰѵ���У�ѧϰ���Ǹ����̶��Ķ�������Ҫ����
            // �����������Ǹ�����Ч�����������Ĵ�����
            // ��Ч����ԽС��ѧϰ�ٶȾͻ�Խ�죬����̫С�ͻ����������������õ�ģ�ͽ���ʧȥ׼ȷ��
            // һ����˵ʹ��Ĭ�ϵ�ֵ�Ϳ���
            // ���ڿ���demo���ҽ�����ֵ�������300����������ܴ󣬱���5000�˵��沿�⣬�����ֵӦ�����ó�500����
            param^.iterations_without_progress_threshold := 300;
            param^.step_mini_batch_target_num := 4;
            param^.step_mini_batch_raster_num := 5;
            training_successed := AI.Metric_ResNet_Train(imgL, param);
            TAI.Free_Metric_ResNet_Parameter(param);

            if training_successed then
              begin
                DoStatus('ѵ���ɹ�');
              end
            else
              begin
                DoStatus('ѵ��ʧ��');
                exit;
              end;
          end;

        DoStatus('��������������� "%s"', [fn.Text]);
        mdnn_hnd := AI.Metric_ResNet_Open_Stream(fn);

        // learnѧϰ��һ�����Ա�����ļ�������ÿ��ѧϰ
        L_fn := umlchangeFileExt(fn, '.learn');
        DoStatus('�������������');
        if umlFileExists(L_fn) then
          begin
            DoStatus('��ȡ����������� "%s"', [L_fn.Text]);
            L_Engine.LoadFromFile(L_fn);
          end
        else
          begin
            DoStatus('Learn��������ѧϰFace����', []);
            L_Engine.Clear;
            tk := GetTimeTick();
            AI.Metric_ResNet_SaveDetectorDefineToLearnEngine(mdnn_hnd, imgL, L_Engine);
            L_Engine.Train;
            DoStatus('ѧϰFace������Learn������ %d ���沿��������ʱ:%dms', [L_Engine.Count, GetTimeTick() - tk]);
            DoStatus('�������������� "%s"', [L_fn.Text]);
            L_Engine.SaveToFile(L_fn);
          end;

        // ��Ϊzai�������������ݼ������ø���ͼƬѵ����������ʵ��Ӧ���У���һ������ʡȴ
        // ֱ��ѡ��720p,1080p�������ͼ�������Դ����
        // û�����ź����ܽ���õ�����
        DoStatus('�����������л���˹Ԥ����.', []);
        new_face_tile := NewRaster();
        tk := GetTimeTick();
        new_face_tile.ZoomFrom(face_tile, face_tile.width * 2, face_tile.height * 2);
        DoStatus('���л���˹Ԥ������ʱ:%dms', [GetTimeTick() - tk]);

        DoStatus('���ڼ������. demoͼƬ�ֱ��� %d*%d', [new_face_tile.width, new_face_tile.height]);
        tk := GetTimeTick();
        face_hnd := AI.Face_Detector_All(new_face_tile);
        DoStatus('����������. ���� %d ����������ʱ:%dms', [AI.Face_chips_num(face_hnd), GetTimeTick() - tk]);

        d := TDrawEngine.Create;
        d.Rasterization.Memory.Assign(face_tile);
        d.SetSize(face_tile);
        for i := 0 to AI.Face_chips_num(face_hnd) - 1 do
          begin
            // ����Ƭ��ȡ����face
            face_raster := AI.Face_chips(face_hnd, i);

            tk := GetTimeTick();
            // ʹ�òв����紦�����Ŷ���face
            // ���Learn����ŷģ��������face_vec
            // AI.Metric_ResNet_Process�Ǹ�api����һ����ʱ�����ὫDNNչ����gpu����һ�����漰���˴���copy�������ıȽ϶��ʱ��
            // ���ڶ��λ����Ƶ�ʵ���ʱ��AI.Metric_ResNet_Process��������ʵʱ��
            face_vec := AI.Metric_ResNet_Process(mdnn_hnd, face_raster);
            disposeObject(face_raster);

            // ʹ��Learn����������Ŷ�������������������ǩ
            // ��Ϊdelphi��freepascalʹ����label�ؼ��֣�label�޷������壬label����token������
            // ��Learn�����ProcessMaxIndexToken�Ƿ������������������ȫ����Kģ�ͣ�Learn�����кܶ෽�����Դ���ŷģ��
            // ��Learn�Ը����˼�������û������
            // �˽����Learn�ļ���ϸ�ڣ����Է����ҵĿ�Դ���̣�https://github.com/PassByYou888/zAnalysis
            face_token := L_Engine.ProcessMaxIndexToken(face_vec);
            DoStatus('������ "%s" ��ʱ:%dms', [face_token, GetTimeTick() - tk]);

            // �������ǿ��԰ѱ�ǩ��������

            // ���������ǷŴ�������������⣬���������ϵҪ��ԭһ��
            face_rect := RectMul(AI.Face_RectV2(face_hnd, i), 0.5);

            // ������
            d.DrawCorner(TV2Rect4.Init(face_rect, 0), DEColor(1, 0.5, 0.5, 1), 20, 5);

            // ����ǩ
            d.BeginCaptureShadow(Vec2(1, 1), 0.9);
            d.DrawText(PFormat('%s', [face_token]), d.Rasterization.Memory.Font.FontSize, face_rect, DEColor(1, 0, 0, 1), False);
            d.EndCaptureShadow;
          end;
        d.Flush;

        DoStatus('��drawEngine��դת����fmx��ʾ');
        TThread.Synchronize(Sender, procedure
          begin
            MemoryBitmapToBitmap(d.Rasterization.Memory, Image1.Bitmap);
          end);
        disposeObject(d);

      finally
          TThread.Synchronize(Sender, procedure
          begin
            FaceRecButton.Enabled := True;
            ResetButton.Enabled := True;
          end);
      end;

      AI.Face_Close(face_hnd);
      AI.Metric_ResNet_Close(mdnn_hnd);
    end);
end;

procedure TFaceRecForm.DoStatusMethod(AText: SystemString; const ID: Integer);
begin
  Memo1.Lines.Add(AText);
end;

procedure TFaceRecForm.FormCreate(Sender: TObject);
begin
  AddDoStatusHook(Self, DoStatusMethod);
  // ��ȡzAI������
  ReadAIConfig;
  // ��һ��������Key����������֤ZAI��Key
  // ���ӷ�������֤Key������������ʱһ���Ե���֤��ֻ�ᵱ��������ʱ�Ż���֤��������֤����ͨ����zAI����ܾ�����
  // �ڳ��������У���������TAI�����ᷢ��Զ����֤
  // ��֤��Ҫһ��userKey��ͨ��userkey�����ZAI������ʱ���ɵ����Key��userkey����ͨ��web���룬Ҳ������ϵ���߷���
  // ��֤key���ǿ����Ӽ����޷����ƽ�
  zAI.Prepare_AI_Engine();

  FaceRecButton.Enabled := False;
  ResetButton.Enabled := False;

  TComputeThread.RunP(nil, nil, procedure(Sender: TComputeThread)
    var
      fn: U_String;
      m64: TMemoryStream64;
    begin
      AI := TAI.OpenEngine();

      DoStatus('��ȡ���ݼ�.');
      imgL := TAI_ImageList.Create;
      fn := umlCombineFileName(TPath.GetLibraryPath, 'lady_face.ImgDataSet');
      imgL.LoadFromFile(fn);

      DoStatus('�����ݼ�չ����ƽ�̹�դ.');
      m64 := TMemoryStream64.Create;
      imgL.SaveToPictureStream(m64);
      m64.Position := 0;
      face_tile := NewRasterFromStream(m64);
      disposeObject(m64);
      DoStatus('����դת����FMXλͼ��ʾ');
      TThread.Synchronize(Sender, procedure
        begin
          MemoryBitmapToBitmap(face_tile, Image1.Bitmap);
          FaceRecButton.Enabled := True;
          ResetButton.Enabled := True;
        end);

      DoStatus('��ʼ��Learn���������');
      DoStatus('Learn����Kά��%d', [zAI.C_Metric_ResNet_Dim]);
      L_Engine := TLearn.CreateClassifier(TLearnType.ltKDT, zAI.C_Metric_ResNet_Dim);
    end);
end;

procedure TFaceRecForm.Image1Click(Sender: TObject);
begin
  MemoryBitmapToBitmap(face_tile, Image1.Bitmap);

end;

procedure TFaceRecForm.Timer1Timer(Sender: TObject);
begin
  DoStatus;
end;

end.