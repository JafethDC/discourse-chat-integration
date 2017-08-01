require 'rails_helper'
require_relative '../dummy_provider'

RSpec.describe DiscourseChat::Manager do
  include_context "dummy provider"

  let(:chan1){DiscourseChat::Channel.create!(provider:'dummy')}
  let(:chan2){DiscourseChat::Channel.create!(provider:'dummy')}

  let(:category) {Fabricate(:category)}

  let(:category) {Fabricate(:category)}
  let(:tag1){Fabricate(:tag)}
  let(:tag2){Fabricate(:tag)}
  let(:tag3){Fabricate(:tag)}

  describe '.process_command' do

    describe 'add new rule' do
        # Not testing how filters are merged here, that's done in .smart_create_rule
        # We just want to make sure the commands are being interpretted correctly

        it 'should add a new rule correctly' do
          response = DiscourseChat::Helper.process_command(chan1, ['watch',category.slug])
          
          expect(response).to eq(I18n.t("chat_integration.provider.dummy.create.created"))

          rule = DiscourseChat::Rule.all.first
          expect(rule.channel).to eq(chan1)
          expect(rule.filter).to eq('watch')
          expect(rule.category_id).to eq(category.id)
          expect(rule.tags).to eq(nil)
        end

        it 'should work with all three filter types' do
          response = DiscourseChat::Helper.process_command(chan1, ['watch',category.slug])

          rule = DiscourseChat::Rule.all.first
          expect(rule.filter).to eq('watch')

          response = DiscourseChat::Helper.process_command(chan1, ['follow',category.slug])

          rule = DiscourseChat::Rule.all.first
          expect(rule.filter).to eq('follow')

          response = DiscourseChat::Helper.process_command(chan1, ['mute',category.slug])

          rule = DiscourseChat::Rule.all.first
          expect(rule.filter).to eq('mute')
        end

        it 'errors on incorrect categories' do
          response = DiscourseChat::Helper.process_command(chan1, ['watch','blah'])

          expect(response).to eq(I18n.t("chat_integration.provider.dummy.not_found.category", name:'blah', list:'uncategorized'))
        end
      
        context 'with tags enabled' do
          before do
            SiteSetting.tagging_enabled = true
          end

          it 'should add a new tag rule correctly' do
            response = DiscourseChat::Helper.process_command(chan1, ['watch',"tag:#{tag1.name}"])

            expect(response).to eq(I18n.t("chat_integration.provider.dummy.create.created"))

            rule = DiscourseChat::Rule.all.first
            expect(rule.channel).to eq(chan1)
            expect(rule.filter).to eq('watch')
            expect(rule.category_id).to eq(nil)
            expect(rule.tags).to eq([tag1.name])
          end

          it 'should work with a category and multiple tags' do
            
            response = DiscourseChat::Helper.process_command(chan1, ['watch',category.slug, "tag:#{tag1.name}", "tag:#{tag2.name}"])
            
            expect(response).to eq(I18n.t("chat_integration.provider.dummy.create.created"))

            rule = DiscourseChat::Rule.all.first
            expect(rule.channel).to eq(chan1)
            expect(rule.filter).to eq('watch')
            expect(rule.category_id).to eq(category.id)
            expect(rule.tags).to contain_exactly(tag1.name, tag2.name)
          end

          it 'errors on incorrect tags' do
            response = DiscourseChat::Helper.process_command(chan1, ['watch',category.slug, "tag:blah"])
            expect(response).to eq(I18n.t("chat_integration.provider.dummy.not_found.tag", name:"blah"))
          end
        end
      end

      describe 'remove rule' do
        it 'removes the rule' do
          rule1 = DiscourseChat::Rule.create(channel: chan1,
                                            filter: 'watch',
                                            category_id: category.id,
                                            tags: [tag1.name, tag2.name]
                                            )

          expect(DiscourseChat::Rule.all.size).to eq(1)
          
          response = DiscourseChat::Helper.process_command(chan1, ['remove','1'])

          expect(response).to eq(I18n.t("chat_integration.provider.dummy.delete.success"))

          expect(DiscourseChat::Rule.all.size).to eq(0)
        end

        it 'errors correctly' do
          response = DiscourseChat::Helper.process_command(chan1, ['remove','1'])
          expect(response).to eq(I18n.t("chat_integration.provider.dummy.delete.error"))          
        end
      end

      describe 'help command' do
        it 'should return the right response' do
          response = DiscourseChat::Helper.process_command(chan1, ["help"])
          expect(response).to eq(I18n.t("chat_integration.provider.dummy.help"))
        end
      end

      describe 'status command' do
        it 'should return the right response' do
          response = DiscourseChat::Helper.process_command(chan1, ['status'])
          expect(response).to eq(DiscourseChat::Helper.status_for_channel(chan1))
        end
      end

      describe 'unknown command' do
        it 'should return the right response' do
          response = DiscourseChat::Helper.process_command(chan1, ['somerandomtext'])
          expect(response).to eq(I18n.t("chat_integration.provider.dummy.parse_error"))
        end
      end
  end

  describe '.status_for_channel' do
    
    context 'with no rules' do
      it 'includes the heading' do
        string = DiscourseChat::Helper.status_for_channel(chan1)
        expect(string).to include('dummy.status.header')
      end

      it 'includes the no_rules string' do
        string = DiscourseChat::Helper.status_for_channel(chan1)
        expect(string).to include('dummy.status.no_rules')
      end
    end

    context 'with some rules' do
      let(:group){Fabricate(:group)}
      before do
        DiscourseChat::Rule.create!(channel: chan1, filter:'watch', category_id:category.id, tags:nil)
        DiscourseChat::Rule.create!(channel: chan1, filter:'mute', category_id:nil, tags:nil)
        DiscourseChat::Rule.create!(channel: chan1, filter:'follow', category_id:nil, tags:[tag1.name])
        DiscourseChat::Rule.create!(channel: chan1, filter:'watch', type: 'group_message', group_id:group.id)
        DiscourseChat::Rule.create!(channel: chan2, filter:'watch', category_id:1, tags:nil)
      end

      it 'displays the correct rules' do
        string = DiscourseChat::Helper.status_for_channel(chan1)
        expect(string.scan('status.rule_string').size).to eq(4)
      end

      it 'only displays tags for rules with tags' do
        string = DiscourseChat::Helper.status_for_channel(chan1)
        expect(string.scan('rule_string_tags_suffix').size).to eq(0)

        SiteSetting.tagging_enabled = true
        string = DiscourseChat::Helper.status_for_channel(chan1)
        expect(string.scan('rule_string_tags_suffix').size).to eq(1)
      end

    end

  end

  describe '.delete_by_index' do
    let(:category2) {Fabricate(:category)}
    let(:category3) {Fabricate(:category)}

    it 'deletes the correct rule' do
      # Three identical rules, with different filters 
      # Status will be sorted by precedence
      # be in this order
      rule1 = DiscourseChat::Rule.create(channel: chan1,
                                      filter: 'mute',
                                      category_id: category.id,
                                      tags: [tag1.name, tag2.name]
                                      )
      rule2 = DiscourseChat::Rule.create(channel: chan1,
                                      filter: 'watch',
                                      category_id: category2.id,
                                      tags: [tag1.name, tag2.name]
                                      )
      rule3 = DiscourseChat::Rule.create(channel: chan1,
                                      filter: 'follow',
                                      category_id: category3.id,
                                      tags: [tag1.name, tag2.name]
                                      )

      expect(DiscourseChat::Rule.all.size).to eq(3)

      expect(DiscourseChat::Helper.delete_by_index(chan1,2)).to eq(:deleted)

      expect(DiscourseChat::Rule.all.size).to eq(2)
      expect(DiscourseChat::Rule.all.map(&:category_id)).to contain_exactly(category.id, category3.id)
    end

    it 'fails gracefully for out of range indexes' do
      rule1 = DiscourseChat::Rule.create(channel: chan1,
                                        filter: 'watch',
                                        category_id: category.id,
                                        tags: [tag1.name, tag2.name]
                                        )

      expect(DiscourseChat::Helper.delete_by_index(chan1,-1)).to eq(false)
      expect(DiscourseChat::Helper.delete_by_index(chan1,0)).to eq(false)
      expect(DiscourseChat::Helper.delete_by_index(chan1,2)).to eq(false)

      expect(DiscourseChat::Helper.delete_by_index(chan1,1)).to eq(:deleted)
    end


  end

  describe '.smart_create_rule' do

    it 'creates a rule when there are none' do
      val = DiscourseChat::Helper.smart_create_rule(channel: chan1,
                                                    filter: 'watch',
                                                    category_id: category.id,
                                                    tags: [tag1.name]
                                                    )
      expect(val).to eq(:created)

      record = DiscourseChat::Rule.all.first
      expect(record.channel).to eq(chan1)
      expect(record.filter).to eq('watch')
      expect(record.category_id).to eq(category.id)
      expect(record.tags).to eq([tag1.name])
    end

    it 'updates a rule when it has the same category and tags' do
      existing = DiscourseChat::Rule.create!(channel:chan1,
                                          filter: 'watch',
                                          category_id: category.id,
                                          tags: [tag2.name, tag1.name]
                                        )

      val = DiscourseChat::Helper.smart_create_rule(channel: chan1,
                                                    filter: 'mute',
                                                    category_id: category.id,
                                                    tags: [tag1.name, tag2.name]
                                                    )

      expect(val).to eq(:updated)

      expect(DiscourseChat::Rule.all.size).to eq(1)
      expect(DiscourseChat::Rule.all.first.filter).to eq('mute')
    end

    it 'updates a rule when it has the same category and filter' do
      existing = DiscourseChat::Rule.create(channel: chan1,
                                            filter: 'watch',
                                            category_id: category.id,
                                            tags: [tag1.name, tag2.name]
                                            )

      val = DiscourseChat::Helper.smart_create_rule(channel: chan1,
                                                    filter: 'watch',
                                                    category_id: category.id,
                                                    tags: [tag1.name, tag3.name]
                                                    )

      expect(val).to eq(:updated)

      expect(DiscourseChat::Rule.all.size).to eq(1)
      expect(DiscourseChat::Rule.all.first.tags).to contain_exactly(tag1.name, tag2.name, tag3.name)
    end

    it 'destroys duplicate rules on save' do
      DiscourseChat::Rule.create!(channel: chan1, filter: 'watch')
      DiscourseChat::Rule.create!(channel: chan1, filter: 'watch')
      expect(DiscourseChat::Rule.all.size).to eq(2)
      val = DiscourseChat::Helper.smart_create_rule(channel: chan1,
                                                    filter: 'watch',
                                                    category_id: nil,
                                                    tags: nil
                                                    )
      expect(val).to eq(:updated)
      expect(DiscourseChat::Rule.all.size).to eq(1)
    end

    it 'returns false on error' do
      val = DiscourseChat::Helper.smart_create_rule(channel: chan1, filter: 'blah')

      expect(val).to eq(false)
    end
  end

  describe '.save_transcript' do

    it 'saves a transcript to redis' do
      key = DiscourseChat::Helper.save_transcript("Some content here")

      expect($redis.get("chat_integration:transcript:#{key}")).to eq("Some content here")
      
      ttl = $redis.pttl("chat_integration:transcript:#{key}")

      # Slight hack since freeze_time doens't work on redis
      expect($redis.pttl("chat_integration:transcript:#{key}")).to be <= (3601*1000)
      expect($redis.pttl("chat_integration:transcript:#{key}")).to be >= (3599*1000)
    end
  end

end