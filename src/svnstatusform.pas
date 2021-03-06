{ Copyright (C) 2008 Darius Blaszijk

  This source is free software; you can redistribute it and/or modify it under
  the terms of the GNU General Public License as published by the Free
  Software Foundation; either version 2 of the License, or (at your option)
  any later version.

  This code is distributed in the hope that it will be useful, but WITHOUT ANY
  WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS
  FOR A PARTICULAR PURPOSE.  See the GNU General Public License for more
  details.

  A copy of the GNU General Public License is available on the World Wide Web
  at <http://www.gnu.org/copyleft/gpl.html>. You can also obtain it by writing
  to the Free Software Foundation, Inc., 59 Temple Place - Suite 330, Boston,
  MA 02111-1307, USA.
}

unit SVNStatusForm;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Process, LCLProc,
  Forms, Controls, Dialogs, ComCtrls, StdCtrls, ButtonPanel, ExtCtrls, Menus,
  // LazUtils
  FileUtil, LazFileUtils,
  // LazSvn
  SVNClasses;

type
  { TSVNStatusFrm }

  TSVNStatusFrm = class(TForm)
    ButtonPanel: TButtonPanel;
    CommitMsgHistoryLabel: TLabel;
    CommitMsgLabel: TLabel;
    Panel1: TPanel;
    ImageList: TImageList;
    mnuOpen: TMenuItem;
    mnuRemove: TMenuItem;
    mnuAdd: TMenuItem;
    mnuRevert: TMenuItem;
    mnuShowDiff: TMenuItem;
    PopupMenu1: TPopupMenu;
    Splitter: TSplitter;
    SVNCommitMsgHistoryComboBox: TComboBox;
    SVNCommitMsgMemo: TMemo;
    SVNFileListView: TListView;
    procedure CancelButtonClick(Sender: TObject);
    procedure FormClose(Sender: TObject; var CloseAction: TCloseAction);
    procedure FormCreate(Sender: TObject);
    procedure FormDestroy(Sender: TObject);
    procedure FormShow(Sender: TObject);
    procedure mnuAddClick(Sender: TObject);
    procedure mnuOpenClick(Sender: TObject);
    procedure mnuRemoveClick(Sender: TObject);
    procedure mnuRevertClick(Sender: TObject);
    procedure mnuShowDiffClick(Sender: TObject);
    procedure OKButtonClick(Sender: TObject);
    procedure PatchButtonClick(Sender: TObject);
    procedure PopupMenu1Popup(Sender: TObject);
    procedure SVNCommitMsgHistoryComboBoxChange(Sender: TObject);
    procedure SVNFileListViewColumnClick(Sender: TObject; Column: TListColumn);
  private
    FRepositoryPath: string;
    SVNStatus: TSVNStatus;
    procedure Initialize({%H-}Data: PtrInt);
    procedure UpdateFilesListView;
    procedure ChangeCursor(ACursor: TCursor);
    procedure UpdateCheckedStatus;
  public
    {path the root of the local working copy}
    property RepositoryPath: string read FRepositoryPath write FRepositoryPath;
  end;

procedure ShowSVNStatusFrm(ARepoPath: string);

var
  SVNStatusFrm: TSVNStatusFrm;

implementation

{$R *.lfm}

uses
  Math,
  SettingsManager, SVNDiffForm, SVNCommitForm;

procedure ShowSVNStatusFrm(ARepoPath: string);
begin
  if not Assigned(SVNStatusFrm) then
    SVNStatusFrm := TSVNStatusFrm.Create(nil);
  SVNStatusFrm.ChangeCursor(crHourGlass);
  SVNStatusFrm.RepositoryPath:=ARepoPath;
  SVNStatusFrm.Show;
end;

{ TSVNStatusFrm }

procedure TSVNStatusFrm.FormShow(Sender: TObject);
begin
  Caption := Format('%s - %s ...', [RepositoryPath, rsLazarusSVNCommit]);
  CommitMsgHistoryLabel.Caption:=rsCommitMsgHistory;
  CommitMsgLabel.Caption:=rsCommitMsg;
  Application.QueueAsyncCall(@Initialize, 0);
end;

procedure TSVNStatusFrm.Initialize(Data: PtrInt);
begin
  SVNStatus := TSVNStatus.Create(RepositoryPath, false);
  SVNStatus.Sort(siChecked, sdAscending);
  UpdateFilesListView;
  ChangeCursor(crDefault);
end;

procedure TSVNStatusFrm.mnuRevertClick(Sender: TObject);
begin
  if Assigned(SVNFileListView.Selected) then
  begin
    ExecuteSvnCommand('revert', RepositoryPath, SVNFileListView.Selected.SubItems[0]);

    //now delete the entry from the list
    SVNStatus.List.Delete(SVNFileListView.Selected.Index);

    //update the listview again
    UpdateFilesListView;
  end;
end;

procedure TSVNStatusFrm.mnuAddClick(Sender: TObject);
begin
  if Assigned(SVNFileListView.Selected) then
  begin
    ExecuteSvnCommand('add', RepositoryPath, SVNFileListView.Selected.SubItems[0]);

    // completely re-read the status
    SVNStatus.Free;
    SVNStatus := TSVNStatus.Create(RepositoryPath, false);
    SVNStatus.Sort(siChecked, sdAscending);
    UpdateFilesListView;
  end;
end;

procedure TSVNStatusFrm.mnuOpenClick(Sender: TObject);
var
  FileName: String;
begin
  if Assigned(SVNFileListView.Selected) then
  begin
    FileName := CreateAbsolutePath(SVNFileListView.Selected.SubItems[0], RepositoryPath);
    //TODO: open in default application
  end;
end;

procedure TSVNStatusFrm.mnuRemoveClick(Sender: TObject);
begin
  if Assigned(SVNFileListView.Selected) then
  begin
    ExecuteSvnCommand('remove --keep-local', RepositoryPath, SVNFileListView.Selected.SubItems[0]);

    // completely re-read the status
    SVNStatus.Free;
    SVNStatus := TSVNStatus.Create(RepositoryPath, false);
    SVNStatus.Sort(siChecked, sdAscending);
    UpdateFilesListView;
  end;
end;

procedure TSVNStatusFrm.mnuShowDiffClick(Sender: TObject);

begin
  if Assigned(SVNFileListView.Selected) then
  begin
    debugln('TSVNStatusFrm.mnuShowDiffClick Path=' ,SVNFileListView.Selected.SubItems[0]);

    if pos(RepositoryPath,SVNFileListView.Selected.SubItems[0]) <> 0 then
      ShowSVNDiffFrm('-r BASE', SVNFileListView.Selected.SubItems[0])
    else
      ShowSVNDiffFrm('-r BASE', AppendPathDelim(RepositoryPath) + SVNFileListView.Selected.SubItems[0]);
  end;
end;

procedure TSVNStatusFrm.OKButtonClick(Sender: TObject);
var
  i: integer;
  CmdLine: string;
  StatusItem : TSVNStatusItem;
  FileName: string;
begin
    //TODO: check if directories also need to be committed
  //      we now only add files to the list, therefore the commit sometimes fails

  UpdateCheckedStatus;
  if SVNCommitMsgMemo.Text = '' then
    if MessageDlg ('No message set.', 'Do you wish to continue?', mtConfirmation,
                  [mbYes, mbNo],0) <> mrYes then
      exit;

  //commit the checked files
  CmdLine := SVNExecutable + ' commit --non-interactive --force-log ';

  for i := 0 to SVNStatus.List.Count - 1 do
  begin
    StatusItem := SVNStatus.List[i];
    if StatusItem.Checked then
    begin
      //add files to SVN if not versioned
      if StatusItem.ItemStatus = 'unversioned' then
        if FileExists(StatusItem.Path) then
          ExecuteSvnCommand('add', ExtractFilePath(StatusItem.Path), StatusItem.Path);

      //add file to commandline for commit
      if pos(RepositoryPath,StatusItem.Path) = 0 then
        CmdLine := CmdLine + ' "' + AppendPathDelim(RepositoryPath) + StatusItem.Path + '"'
      else
        CmdLine := CmdLine + ' "' + StatusItem.Path + '"';
    end;
  end;

  FileName := GetTempFileNameUTF8('','');
  SVNCommitMsgMemo.Lines.SaveToFile(FileName);
  CmdLine := CmdLine + ' --file ' + FileName;

  ShowSVNCommitFrm(CmdLine);
  DeleteFile(FileName);
  Close;
end;

procedure TSVNStatusFrm.PatchButtonClick(Sender: TObject);
var
  i: Integer;
  StatusItem: TSVNStatusItem;
  FileNames: TStringList;
begin
  UpdateCheckedStatus;
  Filenames := TStringList.Create;
  FileNames.Sorted := True;
  for i := 0 to SVNStatus.List.Count - 1 do
  begin
    StatusItem := SVNStatus.List.Items[i];
    if StatusItem.Checked then
      if pos(RepositoryPath,StatusItem.Path) = 0 then
        FileNames.Append(AppendPathDelim(RepositoryPath) + StatusItem.Path)
      else
        FileNames.Append(StatusItem.Path);
  end;
  ShowSVNDiffFrm('-r BASE', FileNames);
end;

procedure TSVNStatusFrm.PopupMenu1Popup(Sender: TObject);
var
  P: TPoint;
  LI: TListItem;
begin
  // make sure the row under the mouse is selected
  P := SVNFileListView.ScreenToControl(Mouse.CursorPos);
  LI := SVNFileListView.GetItemAt(P.X, P.Y);
  if LI <> nil then begin
    SVNFileListView.Selected := LI;
    {$note: using hardcoded column index!}
    if LI.SubItems[2] = 'unversioned' then
      mnuRevert.Enabled := False
    else
      mnuRevert.Enabled := True;
    if (LI.SubItems[2] = 'unversioned') or (LI.SubItems[2] = 'deleted') then begin
      mnuShowDiff.Enabled := False;
      mnuRemove.Enabled := False;
      mnuAdd.Enabled := True;
    end else begin
      mnuShowDiff.Enabled := True;
      mnuRemove.Enabled := True;
      mnuAdd.Enabled := False;
    end;
  end;
end;

procedure TSVNStatusFrm.SVNCommitMsgHistoryComboBoxChange(Sender: TObject);
begin
  with SVNCommitMsgHistoryComboBox do
    if ItemIndex > -1 then
      SVNCommitMsgMemo.Text := Items[ItemIndex];
end;

procedure TSVNStatusFrm.SVNFileListViewColumnClick(Sender: TObject;
  Column: TListColumn);
begin
  case Column.Index of
    0: SVNStatus.ReverseSort(siChecked);
    1: SVNStatus.ReverseSort(siPath);
    2: SVNStatus.ReverseSort(siExtension);
    3: SVNStatus.ReverseSort(siItemStatus);
    4: SVNStatus.ReverseSort(siPropStatus);
    5: SVNStatus.ReverseSort(siAuthor);
    6: SVNStatus.ReverseSort(siRevision);
    7: SVNStatus.ReverseSort(siCommitRevision);
    8: SVNStatus.ReverseSort(siDate);
  end;

  UpdateFilesListView;
end;

procedure TSVNStatusFrm.UpdateFilesListView;
var
  i: integer;
  StatusItem : TSVNStatusItem;
  Path: string;
begin
  SVNFileListView.BeginUpdate;
  SVNFileListView.Clear;
  for i := 0 to SVNStatus.List.Count - 1 do
  begin
    with SVNFileListView.Items.Add do
    begin
      StatusItem := SVNStatus.List.Items[i];
      //checkboxes
      Caption := '';
      Checked := StatusItem.Checked;
      //path
      Path := StatusItem.Path;
      if pos(RepositoryPath, Path) = 1 then
        path := CreateRelativePath(path, RepositoryPath, false);
      SubItems.Add(Path);
      //extension
      SubItems.Add(StatusItem.Extension);
      //file status
      SubItems.Add(StatusItem.ItemStatus);
      //property status
      SubItems.Add(StatusItem.PropStatus);
      //check if file is versioned
      if (LowerCase(StatusItem.ItemStatus) <> 'unversioned') and
         (LowerCase(StatusItem.ItemStatus) <> 'added') then
      begin
        //revision
        SubItems.Add(IntToStr(StatusItem.Revision));
        //commit revision
        SubItems.Add(IntToStr(StatusItem.CommitRevision));
        //author
        SubItems.Add(StatusItem.Author);
        //date
        SubItems.Add(DateTimeToStr(StatusItem.Date));
      end;
    end;
  end;
  SVNFileListView.EndUpdate;
end;

procedure TSVNStatusFrm.ChangeCursor(ACursor: TCursor);
begin
  Cursor := ACursor;
  SVNCommitMsgMemo.Cursor := ACursor;
  SVNFileListView.Cursor := ACursor;
  Self.Cursor := ACursor;
  Application.ProcessMessages;
end;

procedure TSVNStatusFrm.UpdateCheckedStatus;
var
  i : Integer;
begin
  for i := 0 to SVNFileListView.Items.Count - 1 do
    with SVNFileListView.Items[i] do
      SVNStatus.List[Index].Checked := Checked;
end;

procedure TSVNStatusFrm.FormCreate(Sender: TObject);
begin
  mnuShowDiff.Caption := rsShowDiff;
  mnuOpen.Caption := rsOpenFileInEditor;
  mnuRevert.Caption := rsRevert;
  mnuAdd.Caption := rsAdd;
  mnuRemove.Caption := rsRemove;

  ButtonPanel.HelpButton.Caption:=rsCreatePatchFile;
  ButtonPanel.OKButton.Caption:=rsCommit;

  ButtonPanel.OKButton.OnClick:=@OKButtonClick;

  SetColumn(SVNFileListView, 0, 25, '', False);
  SetColumn(SVNFileListView, 1, 300, rsPath, False);
  SetColumn(SVNFileListView, 2, 75, rsExtension, True);
  SetColumn(SVNFileListView, 3, 100, rsFileStatus, True);
  SetColumn(SVNFileListView, 4, 125, rsPropertyStatus, True);
  SetColumn(SVNFileListView, 5, 75, rsRevision, True);
  SetColumn(SVNFileListView, 6, 75, rsCommitRevision, True);
  SetColumn(SVNFileListView, 7, 75, rsAuthor, True);
  SetColumn(SVNFileListView, 8, 75, rsDate, True);

  ImageList.AddResourceName(HInstance, 'menu_svn_diff');
  ImageList.AddResourceName(HInstance, 'menu_svn_revert');

  SVNCommitMsgHistoryComboBox.Items.AddStrings(SettingsMgr.CommitMsg);
end;

procedure TSVNStatusFrm.FormDestroy(Sender: TObject);
begin
  SVNStatusFrm := nil;
end;

procedure TSVNStatusFrm.FormClose(Sender: TObject; var CloseAction: TCloseAction);
var
  index: integer;
  msg: TStrings;
begin
  if SVNCommitMsgMemo.Text <> '' then
  begin
    try
      msg := TStringList.Create;
      msg.AddStrings(SVNCommitMsgHistoryComboBox.Items);

      //delete a previous same mesage from the list, so we don't store duplicates
      index := msg.IndexOf(SVNCommitMsgMemo.Text);
      if index <> -1 then
        msg.Delete(index);

      msg.Insert(0, SVNCommitMsgMemo.Text);

      //limit to 100 entries
      while msg.Count > 99 do
        msg.Delete(100);

      SettingsMgr.CommitMsg := msg;
    finally
      msg.Free;
    end;
  end;
  SVNStatus.Free;
  CloseAction := caFree;
end;

procedure TSVNStatusFrm.CancelButtonClick(Sender: TObject);
begin
  Close;
end;

end.

