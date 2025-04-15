unit LogManager;

interface

uses
  Windows, SysUtils, Classes, FireDAC.UI.Intf, FireDAC.Phys.Intf,
  FireDAC.Stan.Def,
  FireDAC.Stan.Pool, FireDAC.Stan.Async, FireDAC.Phys, FireDAC.Stan.Param,
  FireDAC.DatS, FireDAC.DApt.Intf, FireDAC.DApt, Data.DB, FireDAC.Comp.DataSet,
  FireDAC.Comp.Client, IdBaseComponent, IdComponent, IdTCPConnection,
  IdTCPClient,
  IdHTTP, IdHashMessageDigest, ShellApi;

type
  TLogMode = (lmDatabase = 0, lmFile = 1, lmConsole = 2, lmMsgBox = 3,
    lmHTTP = 4);

type
  TLogType = (ltNotify = 0, ltInfo = 1, ltWarning = 2, ltError = 3,
    ltFatalError = 4, ltDebug = 5);

type
  TLogLevel = (llNormal = 0, llVerbose = 1, llDebug = 2);

type
  TLogManager = class(TObject)
  private
    // Vars
    SL: TStringList;
    http: TIdHttp;
    fdcLog: TFDConnection;
    cmdLog: TFDCommand;
    FModule: String;
    FDBUser: String;
    FDBPass: String;
    FDBHost: String;
    FDBPort: integer;
    FDBName: String;
    FDBCmd: String;
    FHTTPCmd: String;
    FFallback: Boolean;
    FFallbackMode: TLogMode;
    FHandle: HWND;
    FHTTPCmdOk: String;
    FLogMode: TLogMode;
    FLogLevel: TLogLevel;
    FLogDirectory: String;
    // internal functions
    function _LogFileSize(fileName: String): Int64;
    function _LogDirectoryExist: Boolean;
    function _LogTypeToString(logType: TLogType): String;
    function _LogTypeToMsgBoxIcon(logType: TLogType): UINT;
    function _WriteLogDB(logType: TLogType; LogMessage: String): Boolean;
    function _WriteLogFile(logType: TLogType; LogMessage: String): Boolean;
    function _WriteLogConsole(logType: TLogType; LogMessage: String): Boolean;
    function _WriteLogMsgBox(logType: TLogType; LogMessage: String): Boolean;
    function _WriteLogHTTP(logType: TLogType; LogMessage: String): Boolean;

    procedure _SetLogDirectory(Value: String);
    procedure _SetLogMode(Value: TLogMode);
  public
    // properties
    property Module: String read FModule write FModule;
    property Handle: HWND read FHandle write FHandle;
    property DBUser: String read FDBUser write FDBUser;
    property DBPass: String read FDBPass write FDBPass;
    property DBHost: String read FDBHost write FDBHost;
    property DBPort: integer read FDBPort write FDBPort;
    property DBName: String read FDBName write FDBName;
    property DBCmd: String read FDBCmd write FDBCmd;
    property HTTPCmd: String read FHTTPCmd write FHTTPCmd;
    property HTTPCmdOk: String read FHTTPCmdOk write FHTTPCmdOk;
    property Fallback: Boolean read FFallback write FFallback;
    property FallbackMode: TLogMode read FFallbackMode write FFallbackMode;
    property LogMode: TLogMode read FLogMode write FLogMode;
    property LogLevel: TLogLevel read FLogLevel write FLogLevel;
    property LogDirectory: String read FLogDirectory write _SetLogDirectory;
    // Functions
    procedure WriteLog(logType: TLogType; AMessage: String);
    procedure WriteLogAndNotify(logType: TLogType; AMessage: String;
      MsgBoxTitle: String);
    procedure WriteLogAndConsole(logType: TLogType; AMessage: string);
    function LogLevelToStr(LogLevel: TLogLevel): String;
    // Constructors / Destructors
    constructor Create(LogMode: TLogMode; hMainForm: HWND)overload;
    destructor Destroy;
  end;

implementation

function TLogManager.LogLevelToStr(LogLevel: TLogLevel): String;
begin
  case LogLevel of
    llNormal:
      Result := 'Normal';
    llVerbose:
      Result := 'Verbose';
    llDebug:
      Result := 'Debug';
  end;
end;

function TLogManager._LogFileSize(fileName: string): Int64;
var
  sr: TSearchRec;
begin
  if FindFirst(fileName, faAnyFile, sr) = 0 then
    Result := Int64(sr.FindData.nFileSizeHigh) shl Int64(32) +
      Int64(sr.FindData.nFileSizeLow)
  else
    Result := -1;
  FindClose(sr);
end;

function TLogManager._LogDirectoryExist: Boolean;
begin
  try
    Result := (FileGetAttr(Self.FLogDirectory) and faDirectory) > 0;
  except
    Result := false;
  end;
end;

procedure TLogManager._SetLogDirectory(Value: string);
var
  attrib: Cardinal;
begin
  attrib := FileGetAttr(Value);
  // Se o modo de log ou fallback for um arquivo
  if (Self.LogMode = lmFile) or (Self.FallbackMode = lmFile) then
  begin
    // Se o novo diretorio de log existir
    if (attrib and faDirectory) > 0 then
    begin
      Self.FLogDirectory := Value; // Armazena o novo diretório
    end;
  end
  else
  begin
    Self.FLogDirectory := Value;
  end;
end;

procedure TLogManager._SetLogMode(Value: TLogMode);
begin
  case Value of
    lmDatabase:
      Self.FLogMode := Value;
    lmFile:
      if Self._LogDirectoryExist then
        Self.FLogMode := Value;
    lmConsole:
      Self.FLogMode := Value;
    lmMsgBox:
      Self.FLogMode := Value;
    lmHTTP:
      Self.FLogMode := Value;
  else
    Self.FLogMode := Value;
  end;
end;

function TLogManager._LogTypeToString(logType: TLogType): String;
begin
  case logType of
    ltNotify:
      Result := 'Notificação';
    ltInfo:
      Result := 'Informação';
    ltWarning:
      Result := 'Aviso';
    ltError:
      Result := 'Erro';
    ltFatalError:
      Result := 'Erro Fatal';
    ltDebug:
      Result := 'Debug';
  else
    Result := 'Desconhecido';
  end;
end;

function TLogManager._LogTypeToMsgBoxIcon(logType: TLogType): UINT;
begin
  case logType of
    ltNotify:
      Result := MB_ICONINFORMATION;
    ltInfo:
      Result := MB_ICONINFORMATION;
    ltWarning:
      Result := MB_ICONWARNING;
    ltError:
      Result := MB_ICONERROR;
    ltFatalError:
      Result := MB_ICONERROR;
    ltDebug:
      Result := MB_ICONINFORMATION;
  end;
end;

function TLogManager._WriteLogDB(logType: TLogType; LogMessage: string)
  : Boolean;
begin
  try
    Result := false;
    if not fdcLog.Connected then
      fdcLog.Connected := true;
    // informações adicionais do registro de log
    cmdLog.ParamByName('logmessage').Value := '[' + _LogTypeToString(logType) +
      '] ' + LogMessage;
    cmdLog.ParamByName('module').Value := Self.FModule;
    cmdLog.ParamByName('dt').Value := Now;
    // Verifica se o nível de log admite certo log
    case FLogLevel of
      llNormal:
        if (logType <> ltDebug) and (logType <> ltInfo) then
          cmdLog.Execute();
      // Normal não admite notificação de debug ou informação
      llVerbose:
        if logType <> ltDebug then
          cmdLog.Execute(); // Verbose aceita todos menos debug
      llDebug:
        cmdLog.Execute(); // Debug aceita todos os logs
    end;
    Result := true;
  except
    on E: Exception do
    begin
      if Self.FFallback then
      begin
        case Self.FFallbackMode of
          lmDatabase:
            Result := false;
          lmFile:
            Result := Self._WriteLogFile(logType, LogMessage);
          lmConsole:
            Result := Self._WriteLogConsole(logType, LogMessage);
          lmMsgBox:
            Result := Self._WriteLogMsgBox(logType, LogMessage);
          lmHTTP:
            Result := Self._WriteLogHTTP(logType, LogMessage);
        end;
      end;
    end;
  end;
end;

function TLogManager._WriteLogFile(logType: TLogType;
  LogMessage: string): Boolean;
var
  i: integer;
begin
  try
    Result := false;
    if FileExists(Self.FLogDirectory + '\' + FModule + '.log') then
    begin
      if Self._LogFileSize(Self.FLogDirectory + '\' + FModule + '.log') >=
        (1024 * 2000) then
      begin
        // Rename big log file
        for i := 1 to 2048 do
        begin
          if FileExists(Self.FLogDirectory + '\' + FModule + '-' + IntToStr(i) +
            '.log') then
          begin
            Continue;
          end
          else
          begin
            MoveFile(PWideChar(Self.FLogDirectory + '\' + FModule + '.log'),
              PWideChar(Self.FLogDirectory + '\' + FModule + '-' + IntToStr(i)
              + '.log'));
            break;
          end;
        end;
        // Write Log
        case FLogLevel of
          llNormal:
            if (logType <> ltDebug) and (logType <> ltInfo) then
              SL.Add('[' + DateTimeToStr(Now) + ']' + FModule + '- [' +
                _LogTypeToString(logType) + '] ' + LogMessage);
          // Normal não admite notificação de debug ou informação
          llVerbose:
            if logType <> ltDebug then
              SL.Add('[' + DateTimeToStr(Now) + ']' + FModule + '- [' +
                _LogTypeToString(logType) + '] ' + LogMessage);
          // Verbose aceita todos menos debug
          llDebug:
            SL.Add('[' + DateTimeToStr(Now) + ']' + FModule + '- [' +
              _LogTypeToString(logType) + '] ' + LogMessage);
          // Debug aceita todos os logs
        end;
        SL.SaveToFile(Self.FLogDirectory + '\' + FModule + '.log');
        SL.Clear;
        Result := true;
      end
      else
      begin
        // Load current log file, add entry and save it.
        SL.LoadFromFile(Self.FLogDirectory + '\' + FModule + '.log');
        case FLogLevel of
          llNormal:
            if (logType <> ltDebug) and (logType <> ltInfo) then
              SL.Add('[' + DateTimeToStr(Now) + ']' + FModule + '- [' +
                _LogTypeToString(logType) + '] ' + LogMessage);
          // Normal não admite notificação de debug ou informação
          llVerbose:
            if logType <> ltDebug then
              SL.Add('[' + DateTimeToStr(Now) + ']' + FModule + '- [' +
                _LogTypeToString(logType) + '] ' + LogMessage);
          // Verbose aceita todos menos debug
          llDebug:
            SL.Add('[' + DateTimeToStr(Now) + ']' + FModule + '- [' +
              _LogTypeToString(logType) + '] ' + LogMessage);
          // Debug aceita todos os logs
        end;
        SL.SaveToFile(Self.FLogDirectory + '\' + FModule + '.log');
        SL.Clear;
        Result := true;
      end;
    end
    else
    begin
      // Write to a new log file
      case FLogLevel of
        llNormal:
          if (logType <> ltDebug) and (logType <> ltInfo) then
            SL.Add('[' + DateTimeToStr(Now) + ']' + FModule + '- [' +
              _LogTypeToString(logType) + '] ' + LogMessage);
        // Normal não admite notificação de debug ou informação
        llVerbose:
          if logType <> ltDebug then
            SL.Add('[' + DateTimeToStr(Now) + ']' + FModule + '- [' +
              _LogTypeToString(logType) + '] ' + LogMessage);
        // Verbose aceita todos menos debug
        llDebug:
          SL.Add('[' + DateTimeToStr(Now) + ']' + FModule + '- [' +
            _LogTypeToString(logType) + '] ' + LogMessage);
        // Debug aceita todos os logs
      end;
      SL.SaveToFile(Self.FLogDirectory + '\' + FModule + '.log');
      SL.Clear;
      Result := true;
    end;
  except
    on E: Exception do
    begin
      if Self.FFallback then
      begin
        case Self.FFallbackMode of
          lmDatabase:
            Result := Self._WriteLogDB(logType, LogMessage);
          lmFile:
            Result := false;
          lmConsole:
            Result := Self._WriteLogConsole(logType, LogMessage);
          lmMsgBox:
            Result := Self._WriteLogMsgBox(logType, LogMessage);
          lmHTTP:
            Result := Self._WriteLogHTTP(logType, LogMessage);
        end;
      end;
    end;
  end;
end;

function TLogManager._WriteLogConsole(logType: TLogType;
  LogMessage: string): Boolean;
begin
  try
    Result := false;
    case FLogLevel of
      llNormal:
        if (logType <> ltDebug) and (logType <> ltInfo) then
          WriteLn('[' + DateTimeToStr(Now) + ']' + FModule + '-' +
            _LogTypeToString(logType) + LogMessage);
      // Normal não admite notificação de debug ou informação
      llVerbose:
        if logType <> ltDebug then
          WriteLn('[' + DateTimeToStr(Now) + ']' + FModule + '-' +
            _LogTypeToString(logType) + LogMessage);
      // Verbose aceita todos menos debug
      llDebug:
        WriteLn('[' + DateTimeToStr(Now) + ']' + FModule + '-' +
          _LogTypeToString(logType) + LogMessage);
    end;
    Result := true;
  except
    on E: Exception do
    begin
      Result := false;
    end;
  end;
end;

function TLogManager._WriteLogMsgBox(logType: TLogType;
  LogMessage: string): Boolean;
begin
  try
    Result := false;
    case FLogLevel of
      llNormal:
        if (logType <> ltDebug) and (logType <> ltInfo) then
          MessageBox(Self.FHandle, PWideChar(LogMessage),
            PWideChar(Self.FModule), MB_OK + MB_APPLMODAL +
            Self._LogTypeToMsgBoxIcon(logType));
      // Normal não aceita info e debug
      llVerbose:
        if logType <> ltDebug then
          MessageBox(Self.FHandle, PWideChar(LogMessage),
            PWideChar(Self.FModule), MB_OK + MB_APPLMODAL +
            Self._LogTypeToMsgBoxIcon(logType));
      // Verbose aceita todos menos debug
      llDebug:
        MessageBox(Self.FHandle, PWideChar(LogMessage), PWideChar(Self.FModule),
          MB_OK + MB_APPLMODAL + Self._LogTypeToMsgBoxIcon(logType));
    end;
    Result := true;
  except
    on E: Exception do
    begin
      Result := false;
    end;
  end;
end;

function TLogManager._WriteLogHTTP(logType: TLogType;
  LogMessage: string): Boolean;
var
  getCmd: String;
begin
  try
    Result := false;
    getCmd := StringReplace(Self.FHTTPCmd, '%logmsg%', LogMessage,
      [rfIgnoreCase, rfReplaceAll]);
    getCmd := StringReplace(Self.FHTTPCmd, '%logtype%',
      Self._LogTypeToString(logType), [rfIgnoreCase, rfReplaceAll]);
    if http.Get(getCmd) = Self.FHTTPCmdOk then
      Result := true;
  except
    on E: Exception do
    begin
      if Self.FFallback then
      begin
        case Self.FFallbackMode of
          lmDatabase:
            Result := Self._WriteLogDB(logType, LogMessage);
          lmFile:
            Result := Self._WriteLogFile(logType, LogMessage);
          lmConsole:
            Result := Self._WriteLogConsole(logType, LogMessage);
          lmMsgBox:
            Result := Self._WriteLogMsgBox(logType, LogMessage);
          lmHTTP:
            Result := false;
        end;
      end;
    end;
  end;
end;

procedure TLogManager.WriteLog(logType: TLogType; AMessage: string);
begin
  case Self.LogMode of
    lmDatabase:
      Self._WriteLogDB(logType, AMessage);
    lmFile:
      Self._WriteLogFile(logType, AMessage);
    lmConsole:
      Self._WriteLogConsole(logType, AMessage);
    lmMsgBox:
      Self._WriteLogMsgBox(logType, AMessage);
    lmHTTP:
      Self._WriteLogHTTP(logType, AMessage);
  end;
end;

procedure TLogManager.WriteLogAndNotify(logType: TLogType; AMessage: string;
  MsgBoxTitle: String);
begin
  case Self.LogMode of
    lmDatabase:
      Self._WriteLogDB(logType, AMessage);
    lmFile:
      Self._WriteLogFile(logType, AMessage);
    lmConsole:
      Self._WriteLogConsole(logType, AMessage);
    lmMsgBox:
      Self._WriteLogMsgBox(logType, AMessage);
    lmHTTP:
      Self._WriteLogHTTP(logType, AMessage);
  end;
  case Self.LogLevel of
    llNormal:
      if (logType <> ltDebug) and (logType <> ltInfo) then
        MessageBox(Self.FHandle, PWideChar(AMessage),
          PWideChar('[' + Self.FModule + ']' + MsgBoxTitle),
          MB_OK + MB_APPLMODAL + Self._LogTypeToMsgBoxIcon(logType));
    // Normal não aceita info e debug
    llVerbose:
      if logType <> ltDebug then
        MessageBox(Self.FHandle, PWideChar(AMessage),
          PWideChar('[' + Self.FModule + ']' + MsgBoxTitle),
          MB_OK + MB_APPLMODAL + Self._LogTypeToMsgBoxIcon(logType));
    // Verbose aceita todos menos debug
    llDebug:
      MessageBox(Self.FHandle, PWideChar(AMessage),
        PWideChar('[' + Self.FModule + ']' + MsgBoxTitle),
        MB_OK + MB_APPLMODAL + Self._LogTypeToMsgBoxIcon(logType));
  end;
end;

procedure TLogManager.WriteLogAndConsole(logType: TLogType; AMessage: string);
var
  consoleMsg: String;
begin
  case Self.LogMode of
    lmDatabase:
      Self._WriteLogDB(logType, AMessage);
    lmFile:
      Self._WriteLogFile(logType, AMessage);
    lmConsole:
      Self._WriteLogConsole(logType, AMessage);
    lmMsgBox:
      Self._WriteLogMsgBox(logType, AMessage);
    lmHTTP:
      Self._WriteLogHTTP(logType, AMessage);
  end;
  case logType of
    ltNotify:
      consoleMsg := '[Notificação] ' + AMessage;
    ltInfo:
      consoleMsg := '[Informação] ' + AMessage;
    ltWarning:
      consoleMsg := '[Aviso] ' + AMessage;
    ltError:
      consoleMsg := '[Erro] ' + AMessage;
    ltFatalError:
      consoleMsg := '[Erro Crítico] ' + AMessage;
    ltDebug:
      consoleMsg := '[Debug] ' + AMessage;
  end;
  case Self.LogLevel of
    llNormal:
      if (logType <> ltDebug) and (logType <> ltInfo) then
        WriteLn(consoleMsg); // Normal não aceita info e debug
    llVerbose:
      if logType <> ltDebug then
        WriteLn(consoleMsg); // Verbose aceita todos menos debug
    llDebug:
      WriteLn(consoleMsg);
  end;
end;

constructor TLogManager.Create(LogMode: TLogMode; hMainForm: HWND);
begin
  inherited Create();
  http := TIdHttp.Create(nil);
  fdcLog := TFDConnection.Create(nil);
  cmdLog := TFDCommand.Create(nil);
  SL := TStringList.Create;
  Self.FLogMode := LogMode;
  Self.FHandle := hMainForm;
end;

destructor TLogManager.Destroy;
begin
  inherited Destroy();
  http.Destroy;
  fdcLog.Destroy;
  cmdLog.Destroy;
  SL.Destroy;
end;

end.
